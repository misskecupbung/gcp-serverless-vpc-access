terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
resource "google_compute_network" "vpc_main" {
  name                    = "vpc-main"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet_main" {
  name          = "subnet-main"
  ip_cidr_range = "10.1.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_main.id
}

# -----------------------------------------------------------------------------
# Firewall
# -----------------------------------------------------------------------------
resource "google_compute_firewall" "allow_iap" {
  name    = "allow-iap-ssh"
  network = google_compute_network.vpc_main.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

resource "google_compute_firewall" "allow_connector" {
  name    = "allow-vpc-connector"
  network = google_compute_network.vpc_main.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "5432"]
  }

  source_ranges = ["10.8.0.0/28"]
}

# -----------------------------------------------------------------------------
# Cloud Router and Cloud NAT
# -----------------------------------------------------------------------------
resource "google_compute_router" "router" {
  name    = "my-router"
  network = google_compute_network.vpc_main.id
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  name                               = "my-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# -----------------------------------------------------------------------------
# Test VM
# -----------------------------------------------------------------------------
resource "google_compute_instance" "test_vm" {
  name         = "test-vm"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network    = google_compute_network.vpc_main.id
    subnetwork = google_compute_subnetwork.subnet_main.id
  }

  metadata_startup_script = file("${path.module}/../scripts/startup-test.sh")

  tags = ["test-server"]
}

# -----------------------------------------------------------------------------
# Private Service Access (for Cloud SQL private IP)
# -----------------------------------------------------------------------------
resource "google_compute_global_address" "private_ip_range" {
  name          = "private-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_main.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc_main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# -----------------------------------------------------------------------------
# Cloud SQL - PostgreSQL
# -----------------------------------------------------------------------------
resource "google_sql_database_instance" "postgres" {
  name             = "my-postgres"
  database_version = "POSTGRES_14"
  region           = var.region

  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_main.id
    }

    backup_configuration {
      enabled = false
    }
  }

  deletion_protection = false
}

resource "google_sql_database" "app_db" {
  name     = "appdb"
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "app_user" {
  name     = "appuser"
  instance = google_sql_database_instance.postgres.name
  password = "changeme123"
}

# -----------------------------------------------------------------------------
# Serverless VPC Access Connector
# -----------------------------------------------------------------------------
resource "google_vpc_access_connector" "connector" {
  name          = "my-connector"
  region        = var.region
  network       = google_compute_network.vpc_main.id
  ip_cidr_range = "10.8.0.0/28"
  min_instances = 2
  max_instances = 3
  machine_type  = "e2-micro"
}

# -----------------------------------------------------------------------------
# Cloud Run
# -----------------------------------------------------------------------------
resource "google_cloud_run_v2_service" "my_api" {
  name     = "my-api"
  location = var.region

  template {
    containers {
      image = "gcr.io/${var.project_id}/my-api"

      env {
        name  = "DB_HOST"
        value = google_sql_database_instance.postgres.private_ip_address
      }
      env {
        name  = "DB_NAME"
        value = google_sql_database.app_db.name
      }
      env {
        name  = "DB_USER"
        value = google_sql_user.app_user.name
      }
      env {
        name  = "DB_PASS"
        value = google_sql_user.app_user.password
      }
    }

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }
  }

  depends_on = [google_vpc_access_connector.connector]
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.my_api.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}
