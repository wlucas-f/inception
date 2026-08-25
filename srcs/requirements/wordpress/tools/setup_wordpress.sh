#!/bin/bash

set -e

WP_PATH="/var/www/html"

echo "Setting up WordPress..."

# -------------------------------------------------------------------
# Read database password from Docker secret
# -------------------------------------------------------------------

if [ -z "$WORDPRESS_DB_PASSWORD_FILE" ] || [ ! -f "$WORDPRESS_DB_PASSWORD_FILE" ]; then
    echo "ERROR: WORDPRESS_DB_PASSWORD_FILE is not set or secret file does not exist."
    exit 1
fi

WORDPRESS_DB_PASSWORD="$(cat "$WORDPRESS_DB_PASSWORD_FILE")"
export WORDPRESS_DB_PASSWORD

# -------------------------------------------------------------------
# Read WordPress admin password from Docker secret
# -------------------------------------------------------------------

WP_ADMIN_PASSWORD_FILE="/run/secrets/wp_admin_password"

if [ ! -f "$WP_ADMIN_PASSWORD_FILE" ]; then
    echo "ERROR: WordPress admin password secret does not exist."
    exit 1
fi

WP_ADMIN_PASSWORD="$(cat "$WP_ADMIN_PASSWORD_FILE")"

if [ -z "$WP_ADMIN_PASSWORD" ]; then
    echo "ERROR: WordPress admin password is empty."
    exit 1
fi

# -------------------------------------------------------------------
# Wait for MariaDB
# -------------------------------------------------------------------

echo "Waiting for MariaDB..."

until php -r "
\$mysqli = @new mysqli(
    '${WORDPRESS_DB_HOST}',
    '${WORDPRESS_DB_USER}',
    '${WORDPRESS_DB_PASSWORD}',
    '${WORDPRESS_DB_NAME}'
);
if (\$mysqli->connect_errno) {
    exit(1);
}
\$mysqli->close();
exit(0);
"; do
    echo "MariaDB is not ready yet..."
    sleep 2
done

echo "MariaDB is ready."

# -------------------------------------------------------------------
# Download WordPress if necessary
# -------------------------------------------------------------------

if [ ! -f "$WP_PATH/wp-settings.php" ]; then
    echo "Downloading WordPress..."

    wget -q https://wordpress.org/latest.tar.gz -O /tmp/wordpress.tar.gz
    tar -xzf /tmp/wordpress.tar.gz -C /tmp

    cp -a /tmp/wordpress/. "$WP_PATH/"

    rm -rf /tmp/wordpress /tmp/wordpress.tar.gz
fi

# -------------------------------------------------------------------
# Create wp-config.php
# -------------------------------------------------------------------

if [ ! -f "$WP_PATH/wp-config.php" ]; then
    echo "Creating wp-config.php..."

    WP_SALTS="$(wget -qO- https://api.wordpress.org/secret-key/1.1/salt/)"

    cat > "$WP_PATH/wp-config.php" <<EOF
<?php

define('DB_NAME', '${WORDPRESS_DB_NAME}');
define('DB_USER', '${WORDPRESS_DB_USER}');
define('DB_PASSWORD', '${WORDPRESS_DB_PASSWORD}');
define('DB_HOST', '${WORDPRESS_DB_HOST}');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');

\$table_prefix = '${WORDPRESS_TABLE_PREFIX:-wp_}';

${WP_SALTS}

define('WP_DEBUG', false);

if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

require_once ABSPATH . 'wp-settings.php';
EOF

    echo "wp-config.php created."
fi

# -------------------------------------------------------------------
# Permissions
# -------------------------------------------------------------------

chown -R www-data:www-data "$WP_PATH"

# -------------------------------------------------------------------
# Install WordPress
# -------------------------------------------------------------------

echo "Checking WordPress installation..."

if ! wp core is-installed --path="$WP_PATH" --allow-root >/dev/null 2>&1; then
    echo "WordPress is not installed. Installing..."

    wp core install \
        --path="$WP_PATH" \
        --url="https://${DOMAIN_NAME}" \
        --title="${WP_TITLE:-Inception WordPress}" \
        --admin_user="${WP_ADMIN_USER:-admin}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email \
        --allow-root

    echo "WordPress installation complete."
else
    echo "WordPress is already installed."
fi

# -------------------------------------------------------------------
# Final permissions
# -------------------------------------------------------------------

find "$WP_PATH" -type d -exec chmod 750 {} \;
find "$WP_PATH" -type f -exec chmod 640 {} \;

chown -R www-data:www-data "$WP_PATH"

# -------------------------------------------------------------------
# Start PHP-FPM in foreground
# -------------------------------------------------------------------

echo "Starting PHP-FPM..."

exec php-fpm8.2 -F

