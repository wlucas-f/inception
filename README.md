*This project has been created as part of the 42 curriculum by wlucas-f.*

# Inception

## Description

Inception is a system administration project whose goal is to build a small,
self-contained web infrastructure entirely with Docker, using containers that
you write and configure yourself rather than pre-built images pulled from
DockerHub.

The infrastructure is composed of three custom-built services, each running
in its own dedicated container, orchestrated with `docker compose`:

- **NGINX** — the single entrypoint to the whole infrastructure, serving
  HTTPS traffic on port 443 with TLSv1.2/TLSv1.3 only.
- **WordPress + php-fpm** — a WordPress site installed and configured
  automatically on first boot, with no web server bundled inside the
  container (NGINX proxies PHP requests to it over port 9000).
- **MariaDB** — the database backend for WordPress, with no web server
  bundled inside the container either.

Two Docker named volumes persist data across restarts: one for the
WordPress database, one for the WordPress website files. Both are backed
by data physically stored under `/home/wlucas-f/data` on the host. A
dedicated Docker network connects the three containers, and each container
is configured to restart automatically if it crashes.

The whole stack is reachable at `https://wlucas-f.42.fr`, a domain name that
resolves locally to the virtual machine's own IP address.

## Instructions

### Prerequisites

- A Linux virtual machine with Docker Engine and the Docker Compose plugin
  installed.
- `wlucas-f.42.fr` added to `/etc/hosts`, pointing to `127.0.0.1` (or the
  VM's IP if accessed from outside).

### Setup

1. Clone this repository.
2. Create the `secrets/` files (see `DEV_DOC.md` for details) — these are
   intentionally **not** committed to git.
3. Run:

   ```bash
   make
   ```

   This builds all three Docker images from their own Dockerfiles and
   starts the stack via `docker compose`.

4. Visit `https://wlucas-f.42.fr` in a browser (accept the self-signed
   certificate warning) or test with:

   ```bash
   curl -k -I https://wlucas-f.42.fr
   ```

See `USER_DOC.md` and `DEV_DOC.md` for detailed day-to-day usage and
development instructions.

## Project description: Docker and design choices

### Why Docker for this project

Each service (NGINX, WordPress+php-fpm, MariaDB) is built from its own
minimal Debian-based Dockerfile, with no ready-made service images pulled
from DockerHub. This keeps every container lightweight, reproducible, and
fully under our control — the exact opposite of an all-in-one, hand
provisioned server.

### Virtual Machines vs Docker

A Virtual Machine virtualizes an entire operating system — its own kernel,
init system, and full set of system services — on top of a hypervisor.
This gives strong isolation but is heavy: each VM consumes significant RAM,
disk, and boot time, and OS-level maintenance (patching, updates) has to be
repeated for every VM.

Docker containers, by contrast, share the host's kernel and only package
the application and its dependencies. They start in milliseconds instead
of minutes, use a fraction of the resources, and are easy to reproduce
identically across machines through Dockerfiles. The tradeoff is weaker
isolation than a VM (containers share the kernel, so a kernel-level
vulnerability can affect all containers), and no ability to run a different
kernel/OS than the host. For this project, where three lightweight,
independent services need to be reproducible and easy to tear down and
rebuild, Docker is the more appropriate and efficient choice, while the
whole project is still run inside a VM for the isolation that a dedicated
learner environment requires.

### Secrets vs Environment Variables

Environment variables (`.env`) are convenient for non-sensitive
configuration (domain name, database name, usernames) but are visible in
plaintext to anything that can inspect the container (`docker inspect`,
`/proc/<pid>/environ`), and they can easily leak into logs or crash dumps.

Docker secrets are mounted as read-only files inside `/run/secrets/` at
runtime and are never baked into an image layer or exposed through
`docker inspect`. In this project, all passwords (MariaDB root password,
MariaDB user password, WordPress admin and second-user passwords) are
stored as Docker secrets, each backed by its own file under `secrets/`,
while non-sensitive configuration values stay in `.env`. This separation
keeps credentials out of the image, out of `docker-compose.yml`, and out of
git history.

### Docker Network vs Host Network

With `network: host`, a container shares the host's network namespace
directly — no isolation, no private container-to-container DNS, and every
port the container opens is immediately exposed on the host. It is
forbidden by the subject, and for good reason: it removes the ability to
control exactly what is reachable from outside, and breaks the clean
service-to-service communication docker-compose networks provide.

A custom Docker bridge network (`inception-network`, as used here) gives
each container its own network namespace, a private IP, and automatic DNS
resolution by service name (e.g. `wordpress` can reach `mariadb` at the
hostname `mariadb`). Only the ports explicitly published in
`docker-compose.yml` are reachable from the host — in this project, only
NGINX's port 443. This is both more secure and closer to how a real
production deployment would be segmented.

### Docker Volumes vs Bind Mounts

A bind mount maps a specific host directory directly into a container. It
is simple, but it depends entirely on the host's filesystem structure
being correct and pre-existing, gives the container direct, unmanaged
access to arbitrary host paths, and is not portable between machines with
different layouts.

A named volume is managed by Docker itself: Docker owns its lifecycle,
tracks it independently of any single container, and it can be backed up,
inspected, and moved between containers cleanly, without requiring the
caller to know exactly where it lives on disk. This project uses named
volumes (`mariadb_data`, `wordpress_data`) configured with `driver_opts`
of type `none`/`bind` pointed at `/home/wlucas-f/data/{mariadb,wordpress}`
— this satisfies both requirements at once: Docker manages the volume as a
first-class object, while the actual data is still guaranteed to live at a
specific, predictable path on the host as required by the subject.

## Resources

- [Docker Compose documentation](https://docs.docker.com/compose/)
- [Docker Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
- [Docker volumes documentation](https://docs.docker.com/engine/storage/volumes/)
- [Docker secrets documentation](https://docs.docker.com/engine/swarm/secrets/)
- [MariaDB Docker/installation documentation](https://mariadb.com/kb/en/documentation/)
- [WordPress CLI (WP-CLI) documentation](https://wp-cli.org/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [PHP-FPM documentation](https://www.php.net/manual/en/install.fpm.php)

### AI usage

An AI assistant (Claude) was used throughout this project as a debugging
and learning aid, not as a code generator to copy-paste blindly:

- Reviewing the subject requirements against the actual project structure
  and producing a step-by-step verification checklist.
- Writing test/verification shell commands (structure checks, TLS
  protocol checks, volume inspection, restart-policy testing) to validate
  the setup against the subject's requirements.
- Diagnosing a real bug: MariaDB's Debian package auto-initializes
  `/var/lib/mysql` during `apt-get install`, which was silently defeating
  the project's own database-initialization script every time a fresh
  volume was mounted. The AI helped trace the symptom (a `mysqli` "not
  allowed to connect" error) back to this root cause and confirm the fix
  (clearing `/var/lib/mysql` in the Dockerfile after package install).
  All code and configuration were reviewed, tested, and understood before
  being kept in the project.
- Drafting the structure of this documentation (README, USER_DOC, DEV_DOC),
  which was reviewed and adapted to accurately reflect the actual
  implementation.
