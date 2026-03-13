# greenbox

Boilerplate for running a Node.js service that uses the Claude Code SDK inside Docker.

This project provides a ready-to-go Docker setup for Claude SDK apps. It handles mounting OAuth credentials from the host into the container, persisting application output via a `data/` volume, auto-finding free ports, and wrapping it all in simple shell scripts. The Dockerfile uses multi-stage builds with separate dev (live reload) and prod (baked image) targets.

## Project structure

```
├── server.js          # Application entry point
├── package.json       # ES module, start + dev scripts
├── Dockerfile         # Multi-stage: base → dev / prod
├── build.sh           # Build Docker image: ./build.sh [dev]
├── run.sh             # Build + run: ./run.sh [--dev]
├── setup-creds.sh     # One-time credential directory setup (see Dev Notes)
├── .env               # Runtime environment variables
├── .dockerignore
└── .gitignore
```

## Scripts

| Script | Purpose |
|---|---|
| `./build.sh` | Build prod Docker image |
| `./build.sh dev` | Build dev Docker image |
| `./run.sh` | Build and run in prod mode |
| `./run.sh --dev` | Build and run in dev mode |

## Dev mode (`./run.sh --dev`)

Dev mode mounts source code into the container so changes on the host are reflected immediately without rebuilding.

**What gets mounted:**

| Host | Container | Mode |
|---|---|---|
| `~/.claude_mine/.credentials.json` | `/home/node/.claude/.credentials.json` | read-only |
| `./server.js` | `/app/server.js` | read-only |
| `./data/` | `/app/data/` | read-write |

**How it works:**

1. The dev Docker image installs all dependencies
2. `node --watch` watches for file changes and restarts the process automatically
3. You edit files on your host — Node detects the change via the volume mount and restarts
4. The container stays running and the port stays stable

The image only needs to be rebuilt if `package.json` changes.

## Prod mode (`./run.sh`)

Prod mode bakes the source code into the image. Only `./data/` and credentials are mounted at runtime.

Rebuild the image any time the code changes.

## Port allocation

`run.sh` automatically finds the first free port starting at 3000 (up to 3100) and maps it to the container's internal port 3100. The URL is printed on startup.

## Environment variables

Runtime config is passed via `--env-file .env`. See `.env` for available options:

- `PORT` — internal server port (default: 3100)

## Data persistence

Application data is written to `./data/` on the host via a volume mount. This directory persists across container restarts and rebuilds.

## Dockerfile structure

The Dockerfile uses multi-stage builds:

```
base  → node:22-slim, copies package files
  ├── dev  → npm ci (all deps), runs node --watch
  └── prod → npm ci --omit=dev, copies source, runs node
```

`build.sh` selects the target stage via `--target`.

---

## Dev Notes

### Credentials setup (macOS)

On macOS, `~/.claude/` is managed by the Claude desktop app and the OAuth credentials aren't directly accessible for Docker mounts. The workaround is `~/.claude_mine/` — a separate directory where you place a copy of your credentials.

Run the one-time setup:

```bash
./setup-creds.sh
```

This creates `~/.claude_mine/` with correct permissions (700 on the directory, 600 on the file). Then paste the contents of your `.credentials.json` (from a machine where Claude Code is authenticated) into `~/.claude_mine/.credentials.json`.

The SDK uses these OAuth credentials to authenticate API calls. This is separate from an Anthropic API key — billing goes through your Claude subscription.
