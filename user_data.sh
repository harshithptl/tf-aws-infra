#!/bin/bash

mkdir -p /opt/csye6225/src/main/resources

cat <<APP_PROPERTIES > /opt/csye6225/src/main/resources/application.properties
spring.datasource.url=jdbc:postgresql://${db_endpoint}/${db_name}
spring.datasource.username=${db_user}
spring.datasource.password=${db_password}
spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.PostgreSQLDialect
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true
app.s3.bucket.name=${s3_bucket}
logging.file.name=/var/log/webapp/webapp.log
APP_PROPERTIES

systemctl restart webapp.service