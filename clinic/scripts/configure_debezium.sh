#!/bin/bash

MYSQL_COMMAND=/Applications/MAMP/Library/bin/mysql80/bin/mysql
ROOT_USER=root
ROOT_PASSWORD=$(grep "^MYSQL_ROOT_PASSWORD=" .env | cut -d '=' -f 2- | tr -d '"')
DB_NAME=$(grep "^OPENMRS_DB_NAME=" .env | cut -d '=' -f 2- | tr -d '"')
DEBEZIUM_USER=debezium
DEBEZIUM_PASSWORD=$(grep "^MYSQL_DEBEZIUM_PASSWORD=" .env | cut -d '=' -f 2- | tr -d '"')

${MYSQL_COMMAND} -u "$ROOT_USER" -p"$ROOT_PASSWORD" -P 3306 --protocol TCP "$DB_NAME" <<EOF
  CREATE USER '$DEBEZIUM_USER'@'%' IDENTIFIED BY '$DEBEZIUM_PASSWORD';
  GRANT SELECT, INSERT, UPDATE, DELETE, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT 
    ON *.* TO '${DEBEZIUM_USER}'@'%';
  FLUSH PRIVILEGES;
EOF
