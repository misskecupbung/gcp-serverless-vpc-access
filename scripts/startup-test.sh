#!/bin/bash
apt-get update && apt-get install -y nginx postgresql-client
echo "Hello from test-vm" > /var/www/html/index.html
systemctl enable nginx && systemctl start nginx
