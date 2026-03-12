output "cloud_run_url" {
  description = "Cloud Run service URL"
  value       = google_cloud_run_v2_service.my_api.uri
}

output "cloud_sql_private_ip" {
  description = "Private IP of Cloud SQL"
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name"
  value       = google_sql_database_instance.postgres.connection_name
}

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.postgres.name
}

output "test_vm_ip" {
  description = "Internal IP of test-vm"
  value       = google_compute_instance.test_vm.network_interface[0].network_ip
}

output "vpc_connector_id" {
  description = "VPC Connector resource ID"
  value       = google_vpc_access_connector.connector.id
}
