# Greenbox CLI Design

## Purpose

Greenbox is a CLI tool for running Node.js services that use the Claude Code SDK inside Docker. It handles credential mounting, port allocation, container lifecycle, and provides a `bootstrap` command to add the Docker layer to any existing project.

## Repo Structure

```
greenbox/
├── greenbox              # CLI executable (bash)
├── template/             # Files that bootstrap copies into target projects
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── build.sh          # Only dropped with --standalone
│   └── run.sh            # Only dropped with --standalone
├── setup-creds.sh        # One-time macOS credential setup
├── README.md
└── .gitignore
```

No demo app files. This repo is purely tooling + templates.

## Dependencies

- Docker (daemon must be running)
- bash 4+
- `grep`, `sed` — for template substitution and config parsing

No `jq` dependency. The `.greenbox` config is line-based key=value, not JSON (see below).

## CLI Commands

```
greenbox bootstrap [--standalone]    # Add Dockerfile + .dockerignore to cwd
greenbox build [--dev] [<dir>]       # Build image (defaults to cwd)
greenbox run [--dev] [<dir>]         # Build + run container
greenbox stop [<name>]               # Stop + remove container
greenbox list                        # List running greenbox containers
greenbox logs [<name>]               # Tail container logs
greenbox setup-creds                 # Create ~/.claude_mine/ with correct perms
```

All commands that operate on a project default to the current directory and read `.greenbox` for config.

Running `greenbox` with no arguments or an unknown command prints usage help and exits 1.

## .greenbox Config File

Created by `bootstrap` in the target project root. Simple key=value format (no JSON parser needed):

```
name=my-project
port=3100
```

- `name` — required. Used for container and image naming.
- `port` — optional. Default: 3100. The container's internal port AND the starting point for host port scanning.

Commands read this for defaults. CLI args override config values. If `.greenbox` is missing, commands that need it exit with an error telling the user to run `greenbox bootstrap`.

## Container Naming

All containers are named `greenbox-<project-name>`. Image tags follow the same convention:

- Prod: `greenbox-<name>:latest`
- Dev: `greenbox-<name>:dev`

This allows `greenbox list` to filter with `docker ps --filter name=greenbox-` and prevents collisions between projects.

## Bootstrap Behavior

1. Prompt for project name (default: directory name)
2. Prompt for port (default: 3100)
3. Copy `Dockerfile` and `.dockerignore` from template — no placeholders needed in these files, they are generic
4. Create `.greenbox` config file with name and port
5. Append `data/` to `.gitignore` if not already present (create `.gitignore` if missing)
6. If `--standalone`: also copy `build.sh` and `run.sh`, substituting `__PROJECT_NAME__` and `__PORT__` placeholders (these scripts need the project name for image/container naming)
7. Skip any file that already exists — warn the user, never overwrite

## Template Dockerfile

Multi-stage build:

```dockerfile
FROM node:22-slim AS base
WORKDIR /app
COPY package*.json ./

FROM base AS dev
RUN npm ci
CMD ["npm", "run", "dev"]

FROM base AS prod
RUN npm ci --omit=dev
COPY . .
CMD ["node", "server.js"]
```

Generic — no project-name-specific content. Works for any Node.js project. The target project is expected to have a `package.json` with `start` and `dev` scripts.

## Build Command

`greenbox build [--dev] [<dir>]`

- Reads `.greenbox` from target dir for project name
- Dev: `docker build --target dev -t greenbox-<name>:dev <dir>`
- Prod: `docker build --target prod -t greenbox-<name>:latest <dir>`

## Run Command

`greenbox run [--dev] [<dir>]`

- Reads `.greenbox` from target dir for project name and port
- Verifies Claude credentials at `~/.claude_mine/.credentials.json` — exits with error if missing, tells user to run `greenbox setup-creds`
- Creates `<dir>/data/` if it doesn't exist (avoids Docker creating it as root)
- Auto-finds first free host port starting at the configured port, scanning up to 20 ports. Exits with error if none found.
- Builds image (calls build internally)
- Stops existing container with same name if running
- Passes `--env-file .env` if an `.env` file exists in the project dir (silently skipped if absent)
- Runs container with:
  - `-p <host-port>:<configured-port>` (host port is the auto-found free port, container port is from config)
  - `~/.claude_mine/.credentials.json` → `/home/node/.claude/.credentials.json` (read-only)
  - `<dir>/data/` → `/app/data/` (read-write)
  - In dev mode: additional source mounts (see Dev Mode section)
- Prints URL and log command on startup

## Stop Command

`greenbox stop [<name>]`

- Defaults to project name from `.greenbox` in cwd
- The argument is the project name, not the container name — the tool prefixes `greenbox-`
- Runs `docker rm -f greenbox-<name>`

## List Command

`greenbox list`

- Runs `docker ps -a --filter name=greenbox- --format` with formatted output
- Shows container name (without `greenbox-` prefix), status, and port mapping

## Logs Command

`greenbox logs [<name>]`

- Defaults to project name from `.greenbox` in cwd
- Runs `docker logs -f greenbox-<name>`

## Setup-Creds Command

`greenbox setup-creds`

- Creates `~/.claude_mine/` (mode 700) and `.credentials.json` (mode 600)
- If file already exists, just fixes permissions
- Tells user to paste their OAuth credentials (the JSON blob from a machine where Claude Code is authenticated via `claude login`)

## Dev Mode Source Mounting

In dev mode, source files need to be available in the container for live reload. The approach: mount the entire project directory at `/app/`, but use a named Docker volume for `node_modules` so the image's installed dependencies aren't shadowed by the bind mount.

```
-v "<dir>:/app"
-v "greenbox-<name>-node_modules:/app/node_modules"
-v "<dir>/data:/app/data"
```

The named volume `greenbox-<name>-node_modules` is populated on first run by the image's `npm ci` output. It persists across container restarts so deps don't need to be reinstalled each time. The volume is only recreated when the image is rebuilt (i.e., when `package.json` changes).

## Standalone Mode

When `bootstrap --standalone` is used, `build.sh` and `run.sh` are dropped into the project. These are self-contained scripts that replicate the core greenbox logic:

- `build.sh` — builds dev/prod images using the project name from `.greenbox`
- `run.sh` — full run logic: credential check, port scanning, build, stop existing, mount, run

The standalone scripts read `.greenbox` for config, same as the CLI. A project bootstrapped with `--standalone` works without the `greenbox` CLI installed.

## What Happens to Current Files

- `server.js`, `package.json`, `.env`, current `Dockerfile`, `build.sh`, `run.sh`, `.dockerignore` — removed from repo root. These were demo/boilerplate files.
- `setup-creds.sh` — stays in repo root as a standalone script, also callable via `greenbox setup-creds`
- `README.md` — rewritten to document the CLI
