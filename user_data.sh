#!/bin/bash

# Install AWS CLI and jq if not already installed
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -o awscliv2.zip
sudo ./aws/install
sudo apt-get install -y jq

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${secret_id}" \
  --region "${region}" \
  --query 'SecretString' \
  --output text 2>&1)

if [ -z "$SECRET_JSON" ] || [ "$SECRET_JSON" = "null" ]; then
  exit 1
fi

DB_USER=$(echo "$SECRET_JSON" | jq -r '.username')
DB_PASS=$(echo "$SECRET_JSON" | jq -r '.password')

mkdir -p /opt/csye6225/src/main/resources

cat <<APP_PROPERTIES > /opt/csye6225/src/main/resources/application.properties
spring.datasource.url=jdbc:postgresql://${db_endpoint}/${db_name}
spring.datasource.username=$${DB_USER}
spring.datasource.password=$${DB_PASS}
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true
app.s3.bucket.name=${s3_bucket}
logging.file.name=/var/log/webapp/webapp.log
APP_PROPERTIES

systemctl restart webapp.service