#!/bin/bash

set -e

MYSQL_DATA_DIR="/var/lib/mysql"
MYSQL_SOCKET="/run/mysqld/mysqld.sock"

echo "Starting MariaDB initialization..."

# -------------------------------------------------------------------
# Read secrets
# -------------------------------------------------------------------

if [ -z "$MYSQL_ROOT_PASSWORD_FILE" ] || [ ! -f "$MYSQL_ROOT_PASSWORD_FILE" ]; then
    echo "ERROR: MYSQL_ROOT_PASSWORD_FILE is not set or secret file does not exist."
    exit 1
fi

if [ -z "$MYSQL_PASSWORD_FILE" ] || [ ! -f "$MYSQL_PASSWORD_FILE" ]; then
    echo "ERROR: MYSQL_PASSWORD_FILE is not set or secret file does not exist."
    exit 1
fi

MYSQL_ROOT_PASSWORD="$(cat "$MYSQL_ROOT_PASSWORD_FILE")"
MYSQL_PASSWORD="$(cat "$MYSQL_PASSWORD_FILE")"

if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo "ERROR: MariaDB root password is empty."
    exit 1
fi

if [ -z "$MYSQL_PASSWORD" ]; then
    echo "ERROR: MariaDB user password is empty."
    exit 1
fi

# -------------------------------------------------------------------
# Prepare directories
# -------------------------------------------------------------------

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

mkdir -p /var/log/mysql
chown -R mysql:mysql /var/log/mysql

# -------------------------------------------------------------------
# Initialize database directory if necessary
# -------------------------------------------------------------------

if [ ! -d "$MYSQL_DATA_DIR/mysql" ]; then

    echo "Initializing MariaDB data directory..."

    mariadb-install-db \
        --user=mysql \
        --datadir="$MYSQL_DATA_DIR" \
        --auth-root-authentication-method=normal

    # ---------------------------------------------------------------
    # Start temporary MariaDB server
    # ---------------------------------------------------------------

    echo "Starting temporary MariaDB server for setup..."

    mysqld \
        --user=mysql \
        --datadir="$MYSQL_DATA_DIR" \
        --socket="$MYSQL_SOCKET" \
        --skip-networking \
        --log-error=/var/log/mysql/error.log &

    pid="$!"

    # ---------------------------------------------------------------
    # Wait for MariaDB
    # ---------------------------------------------------------------

    echo "Waiting for MariaDB to be ready..."

    for i in $(seq 1 30); do
        if mysqladmin \
            --socket="$MYSQL_SOCKET" \
            --user=root \
            ping \
            --silent 2>/dev/null
        then
            echo "MariaDB is ready!"
            break
        fi

        if ! kill -0 "$pid" 2>/dev/null; then
            echo "ERROR: MariaDB temporary server died."
            cat /var/log/mysql/error.log || true
            exit 1
        fi

        sleep 1
    done

    if ! mysqladmin \
        --socket="$MYSQL_SOCKET" \
        --user=root \
        ping \
        --silent 2>/dev/null
    then
        echo "ERROR: MariaDB did not become ready."
        cat /var/log/mysql/error.log || true
        exit 1
    fi

    # ---------------------------------------------------------------
    # Configure database and users
    # ---------------------------------------------------------------

    echo "Running setup SQL..."

    mysql \
        --socket="$MYSQL_SOCKET" \
        --user=root << EOF
ALTER USER 'root'@'localhost'
    IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';

CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;

CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%'
    IDENTIFIED BY '${MYSQL_PASSWORD}';

GRANT ALL PRIVILEGES
    ON \`${MYSQL_DATABASE}\`.*
    TO '${MYSQL_USER}'@'%';

FLUSH PRIVILEGES;
EOF

    echo "Database '${MYSQL_DATABASE}' configured."
    echo "User '${MYSQL_USER}' configured."

    # ---------------------------------------------------------------
    # Shut down temporary server
    # ---------------------------------------------------------------

    echo "Shutting down temporary MariaDB..."

    mysqladmin \
        --socket="$MYSQL_SOCKET" \
        --user=root \
        --password="$MYSQL_ROOT_PASSWORD" \
        shutdown

    wait "$pid" || true

else

    echo "MariaDB data directory already initialized."
    echo "Skipping database initialization."

fi

# -------------------------------------------------------------------
# Start MariaDB normally
# -------------------------------------------------------------------

echo "Starting MariaDB..."

exec mysqld \
    --user=mysql \
    --datadir="$MYSQL_DATA_DIR" \
    --socket="$MYSQL_SOCKET" \
    --bind-address=0.0.0.0

