# User Documentation

This document explains, in simple terms, how to use the Inception stack as
an end user or administrator — no development knowledge required.

## 1. What services does this stack provide?

The stack is made of three containers working together:

| Service       | What it does                                                        |
|---------------|----------------------------------------------------------------------|
| **NGINX**     | The only entrypoint into the stack. Serves the website over HTTPS (port 443, TLSv1.2/1.3 only). |
| **WordPress** | The actual website / CMS, running behind PHP-FPM.                   |
| **MariaDB**   | The database that stores all WordPress content (pages, posts, users). |

You never access WordPress or MariaDB directly — everything goes through
NGINX.

## 2. Starting and stopping the project

From the root of the repository:

**Start (build + run) everything:**
```bash
make
```

**Stop everything (containers stay, data is kept):**
```bash
make down
```
(or, if there is no `down` target: `docker compose -f srcs/docker-compose.yml down`)

**Stop and remove everything, including built images (data volumes are
kept unless you also remove them manually):**
```bash
make fclean
```

**Check what's currently running:**
```bash
docker ps
```
You should see three containers: `nginx`, `wordpress`, and `mariadb`, all
with status `Up`.

## 3. Accessing the website and the admin panel

- **Website:** open `https://wlucas-f.42.fr` in your browser.
  - The certificate is self-signed (generated locally for the project), so
    your browser will show a security warning the first time — this is
    expected. Choose "proceed anyway" / "accept the risk".
- **Admin panel:** open `https://wlucas-f.42.fr/wp-admin`.
  - Log in with the administrator account (see below for how to find the
    username and password).

## 4. Locating and managing credentials

All passwords are stored as separate files in the `secrets/` folder at the
project root (never inside `.env`, never committed to git):

| File                        | What it's for                          |
|------------------------------|-----------------------------------------|
| `db_root_password.txt`      | MariaDB root password                   |
| `db_password.txt`           | MariaDB application user password       |
| `wp_admin_password.txt`     | WordPress administrator password        |
| `wp_user_password.txt`      | WordPress second (non-admin) user password |

Usernames (non-sensitive) are set in `srcs/.env`:
- `WP_ADMIN_USER` — the WordPress administrator's username
- `WP_USER` — the second WordPress user's username

To read a password (for example, to log into `/wp-admin`):
```bash
cat secrets/wp_admin_password.txt
```

To change a password, edit the relevant file in `secrets/` and restart the
stack:
```bash
docker compose -f srcs/docker-compose.yml up -d --build
```

## 5. Checking that services are running correctly

**Are all containers up?**
```bash
docker ps -a
```
All three (`nginx`, `wordpress`, `mariadb`) should show `Up`, not
`Exited` or `Restarting`.

**Is the website actually responding?**
```bash
curl -k -I https://wlucas-f.42.fr
```
A healthy response looks like `HTTP/2 200`.

**Something looks wrong — check the logs:**
```bash
docker logs nginx
docker logs wordpress
docker logs mariadb
```

**Is the data persisting?** Your WordPress files and database live on the
host under `/home/wlucas-f/data/wordpress` and `/home/wlucas-f/data/mariadb`
respectively. Stopping and restarting the stack (`down` then `up`, without
deleting these folders) will not lose any content.
