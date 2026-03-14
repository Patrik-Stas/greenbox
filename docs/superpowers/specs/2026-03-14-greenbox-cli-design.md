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

## .greenbox Config File

Created by `bootstrap` in the target project root:

```json
{ "name": "my-project", "port": 3100 }
```

Commands read this for the project name and default port. CLI args override config values.

## Container Naming

All containers are prefixed `greenbox-<project-name>`. This allows `greenbox list` to filter with `docker ps --filter name=greenbox-` and prevents collisions between projects.

## Bootstrap Behavior

1. Prompt for project name (default: directory name)
2. Prompt for port (default: 3100)
3. Copy `Dockerfile` and `.dockerignore` from template, substituting `__PROJECT_NAME__` placeholder
4. Create `.greenbox` config file
5. Append `data/` to `.gitignore` if not already present
6. If `--standalone`: also copy `build.sh` and `run.sh` with substitutions
7. Skip any file that already exists — warn the user, never overwrite

## Template Dockerfile

Multi-stage build, same pattern as current:

```
base  → node:22-slim, copies package files
  ├── dev  → npm ci (all deps), node --watch
  └── prod → npm ci --omit=dev, copies source, node
```

Generic — works for any Node.js project structure.

## Build Command

`greenbox build [--dev] [<dir>]`

- Reads `.greenbox` from target dir for project name
- Runs `docker build --target <dev|prod> -t greenbox-<name>[:<dev>] <dir>`

## Run Command

`greenbox run [--dev] [<dir>]`

- Reads `.greenbox` from target dir for project name and port
- Verifies Claude credentials at `~/.claude_mine/.credentials.json`
- Auto-finds first free host port starting at the configured port (range: configured port to configured port + 100)
- Builds image (calls build internally)
- Stops existing container with same name if running
- Runs container with mounts:
  - `~/.claude_mine/.credentials.json` → `/home/node/.claude/.credentials.json` (read-only)
  - `<dir>/data/` → `/app/data/` (read-write)
  - In dev mode: source files mounted read-only for live reload
- Prints URL and log command on startup

## Stop Command

`greenbox stop [<name>]`

- Defaults to project name from `.greenbox` in cwd
- Runs `docker rm -f greenbox-<name>`

## List Command

`greenbox list`

- Runs `docker ps --filter name=greenbox-` with formatted output
- Shows container name, status, and port mapping

## Logs Command

`greenbox logs [<name>]`

- Defaults to project name from `.greenbox` in cwd
- Runs `docker logs -f greenbox-<name>`

## Setup-Creds Command

`greenbox setup-creds`

- Creates `~/.claude_mine/` (mode 700) and `.credentials.json` (mode 600)
- Same logic as current `setup-creds.sh`

## Dev Mode Source Mounting

In dev mode, the run command needs to mount source files for live reload. The question is which files to mount. Approach: mount the entire project directory read-only at `/app/` and overlay `data/` as read-write. This avoids needing to know the project's file structure.

```
-v "<dir>:/app:ro"
-v "<dir>/data:/app/data"
```

## What Happens to Current Files

- `server.js`, `package.json`, `.env`, current `Dockerfile`, `build.sh`, `run.sh` — removed from repo root. These were demo/boilerplate files.
- `setup-creds.sh` — stays in repo root as a standalone script, also callable via `greenbox setup-creds`
- `README.md` — rewritten to document the CLI
