# Developer Documentation

This document explains how to set up, build, run, and manage the Inception
project from a developer's perspective.

## 1. Setting up the environment from scratch

### Prerequisites

- A Linux Virtual Machine (the project must run inside a VM, not directly
  on bare metal or in a nested container environment).
- Docker Engine and the Docker Compose plugin installed.
- `sudo` access on the VM (needed to inspect/clean host-mounted data
  directories under `/home/<login>/data`).

### Repository layout

```
.
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── secrets/                     # NOT committed to git
│   ├── db_password.txt
│   ├── db_root_password.txt
│   ├── wp_admin_password.txt
│   └── wp_user_password.txt
└── srcs/
    ├── docker-compose.yml
    ├── .env                      # NOT committed to git
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── conf/50-server.cnf
        │   └── tools/init_db.sh
        ├── nginx/
        │   ├── Dockerfile
        │   ├── conf/nginx.conf.template
        │   └── tools/generate_ssl.sh
        └── wordpress/
            ├── Dockerfile
            ├── conf/www.conf
            └── tools/setup_wordpress.sh
```

### Configuration files to create before the first run

**`secrets/` — one password per file, no trailing content beyond the
password itself:**
```bash
mkdir -p secrets
openssl rand -base64 20 > secrets/db_root_password.txt
openssl rand -base64 20 > secrets/db_password.txt
openssl rand -base64 20 > secrets/wp_admin_password.txt
openssl rand -base64 20 > secrets/wp_user_password.txt
chmod 600 secrets/*.txt
```

**`srcs/.env` — non-sensitive configuration:**
```env
DOMAIN_NAME=wlucas-f.42.fr
MYSQL_DATABASE=wordpress_db
MYSQL_USER=wp_user
WP_TITLE=Inception
WP_ADMIN_USER=wlucas-f
WP_ADMIN_EMAIL=wlucas-f@student.42porto.com
WP_USER=jdoe
WP_USER_EMAIL=jdoe@student.42porto.com
```

**Domain resolution** — add to `/etc/hosts`:
```
127.0.0.1   wlucas-f.42.fr
```

Both `secrets/` and `.env` are listed in `.gitignore` and must never be
committed.

## 2. Building and launching with the Makefile and Docker Compose

**Build all images and start the stack:**
```bash
make
```
This runs, under the hood:
```bash
docker compose -f srcs/docker-compose.yml build
docker compose -f srcs/docker-compose.yml up -d
```

**Rebuild after changing a Dockerfile or a tool script:**
```bash
docker compose -f srcs/docker-compose.yml up -d --build
```

**Stop the stack (keep data and images):**
```bash
docker compose -f srcs/docker-compose.yml down
```

**Full teardown (containers, network, and — if you add `-v` — volume
objects too; this does NOT delete the actual bind-mounted host data):**
```bash
docker compose -f srcs/docker-compose.yml down -v
```

## 3. Managing containers and volumes

**List running containers:**
```bash
docker ps -a
```

**Follow logs for a specific service:**
```bash
docker logs -f mariadb
docker logs -f wordpress
docker logs -f nginx
```

**Open a shell inside a container:**
```bash
docker exec -it wordpress bash
docker exec -it mariadb bash
```

**Inspect the restart policy:**
```bash
docker inspect mariadb --format='{{.HostConfig.RestartPolicy}}'
```

**List volumes and confirm where they actually point:**
```bash
docker volume ls
docker volume inspect srcs_mariadb_data
docker volume inspect srcs_wordpress_data
```

**Check WordPress users directly:**
```bash
docker exec wordpress wp user list --allow-root --path=/var/www/html
```

**Check MariaDB grants/databases directly:**
```bash
docker exec mariadb mysql -u root -p"$(cat secrets/db_root_password.txt)" \
    -e "SELECT User, Host FROM mysql.user; SHOW DATABASES;"
```

## 4. Where project data is stored and how it persists

Both persistent volumes are Docker **named volumes**, but configured with
`driver_opts` (`type: none`, `o: bind`) so that their actual data lives at
a fixed, predictable location on the host rather than Docker's internal
storage path:

| Named volume            | Mounted in container at | Actual host path                        |
|--------------------------|--------------------------|-------------------------------------------|
| `mariadb_data`           | `/var/lib/mysql`         | `/home/wlucas-f/data/mariadb`             |
| `wordpress_data`         | `/var/www/html`          | `/home/wlucas-f/data/wordpress`           |

Because this data lives outside the containers' writable layers, running
`docker compose down` and `docker compose up` again does **not** lose any
WordPress content or database rows — only removing the actual host
directories (`/home/wlucas-f/data/...`) or explicitly deleting the volumes
resets the stack to a blank state.

### Important gotcha (worth knowing before debugging database issues)

Installing `mariadb-server` via `apt-get` on Debian automatically runs a
postinstall step that initializes a stub database inside the image layer
at `/var/lib/mysql`. If this stub is not removed in the Dockerfile, Docker's
volume "copy-up" behavior will populate any freshly created empty named
volume with that stub content the moment the container starts — making the
project's own `init_db.sh` script wrongly believe the database is "already
initialized" and skip real setup (grants, database creation) forever. This
project's `mariadb/Dockerfile` explicitly runs
`rm -rf /var/lib/mysql/*` right after the package install to avoid this.

### Resetting to a completely clean state

```bash
docker compose -f srcs/docker-compose.yml down
sudo rm -rf /home/wlucas-f/data/mariadb/*
sudo rm -rf /home/wlucas-f/data/wordpress/*
docker volume rm srcs_mariadb_data srcs_wordpress_data
docker compose -f srcs/docker-compose.yml up -d --build
```
