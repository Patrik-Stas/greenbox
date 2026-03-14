# greenbox

CLI tool for running Node.js services that use the Claude Code SDK inside Docker. Handles credential mounting, port allocation, container lifecycle, and bootstrapping new projects with the Docker layer.

## Installation

Add the `greenbox` script to your PATH:

```bash
ln -s /path/to/greenbox/greenbox /usr/local/bin/greenbox
```

## Quick Start

```bash
greenbox setup-creds                # one-time: set up credential directory
cd my-project                       # go to your Node.js project
greenbox bootstrap                  # add Dockerfile + config
greenbox run --dev                  # build and run in dev mode
```

## Commands

| Command | Purpose |
|---|---|
| `greenbox bootstrap [--standalone]` | Add Dockerfile + .dockerignore to current directory |
| `greenbox build [--dev] [<dir>]` | Build Docker image |
| `greenbox run [--dev] [<dir>]` | Build and run container |
| `greenbox stop [<name>]` | Stop and remove container |
| `greenbox list` | List all greenbox containers |
| `greenbox logs [<name>]` | Tail container logs |
| `greenbox setup-creds` | Set up `~/.claude_mine/` credential directory |

## Bootstrap

`greenbox bootstrap` adds Docker files to an existing project without touching your source code. It prompts for a project name and port, then creates:

- `Dockerfile` — multi-stage build (dev + prod targets)
- `.dockerignore`
- `.greenbox` — project config (name, port)
- Appends `data/` to `.gitignore`

With `--standalone`, it also drops `build.sh` and `run.sh` so the project works without the `greenbox` CLI installed.

Existing files are never overwritten.

## .greenbox Config

```
name=my-project
port=3100
```

- `name` — used for container and image naming (`greenbox-<name>`)
- `port` — container's internal port and starting point for host port scanning

## Dev vs Prod Mode

**Dev mode** (`greenbox run --dev`) mounts your project directory into the container for live reload. A named Docker volume preserves `node_modules` so dependencies survive container restarts. Edit files on your host — `node --watch` restarts automatically.

**Prod mode** (`greenbox run`) bakes source code into the image. Only `data/` and credentials are mounted. Rebuild when code changes.

## Port Allocation

`greenbox run` auto-finds the first free host port starting at the configured port, scanning up to 20 ports. The URL is printed on startup.

## Dockerfile Structure

```
base  → node:22-slim, copies package files
  ├── dev  → npm ci (all deps), runs npm run dev
  └── prod → npm ci --omit=dev, copies source, runs node
```

---

## Dev Notes

### Credentials setup (macOS)

On macOS, `~/.claude/` is managed by the Claude desktop app and the OAuth credentials aren't directly accessible for Docker mounts. The workaround is `~/.claude_mine/` — a separate directory where you place a copy of your credentials.

```bash
greenbox setup-creds
```

This creates `~/.claude_mine/` with correct permissions (700 on the directory, 600 on the file). Then paste your `.credentials.json` content (from a machine where Claude Code is authenticated via `claude login`) into `~/.claude_mine/.credentials.json`.

The SDK uses these OAuth credentials to authenticate API calls. This is separate from an Anthropic API key — billing goes through your Claude subscription.
