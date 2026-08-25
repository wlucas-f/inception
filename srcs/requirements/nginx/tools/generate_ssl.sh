#!/bin/bash

set -e

: "${DOMAIN_NAME:=localhost}"

echo "Configuring Nginx for ${DOMAIN_NAME}..."

# -------------------------------------------------------------------
# Generate nginx.conf from template
# -------------------------------------------------------------------

envsubst '${DOMAIN_NAME}' \
    < /etc/nginx/nginx.conf.template \
    > /etc/nginx/nginx.conf

# -------------------------------------------------------------------
# Generate self-signed SSL certificate
# -------------------------------------------------------------------

mkdir -p /etc/nginx/ssl

if [ ! -f /etc/nginx/ssl/nginx.crt ] || [ ! -f /etc/nginx/ssl/nginx.key ]; then
    echo "Generating SSL certificate for ${DOMAIN_NAME}..."

    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/nginx.key \
        -out /etc/nginx/ssl/nginx.crt \
        -subj "/C=PT/ST=Braga/L=Braga/O=42/CN=${DOMAIN_NAME}"

    chmod 600 /etc/nginx/ssl/nginx.key
    chmod 644 /etc/nginx/ssl/nginx.crt

    echo "SSL certificate generated."
else
    echo "SSL certificate already exists."
fi

# -------------------------------------------------------------------
# Test nginx configuration
# -------------------------------------------------------------------

echo "Testing nginx configuration..."

nginx -t

echo "Nginx configuration test passed."

# -------------------------------------------------------------------
# Start nginx in foreground
# -------------------------------------------------------------------

echo "Starting Nginx..."

exec nginx -g "daemon off;"

