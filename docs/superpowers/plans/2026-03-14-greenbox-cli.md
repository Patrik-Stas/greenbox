# Greenbox CLI Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform greenbox from a demo project into a CLI tool that manages Docker containers for Claude SDK Node.js apps.

**Architecture:** Single bash executable (`greenbox`) with subcommands. Template files live in `template/` and get copied into target projects via `greenbox bootstrap`. Config stored in `.greenbox` key=value files per project.

**Tech Stack:** Bash 4+, Docker, grep for config parsing

**Spec:** `docs/superpowers/specs/2026-03-14-greenbox-cli-design.md`

---

## Chunk 1: Cleanup and Templates

### Task 1: Remove demo files from repo root

**Files:**
- Delete: `server.js`
- Delete: `package.json`
- Delete: `.env`
- Delete: `Dockerfile`
- Delete: `build.sh`
- Delete: `run.sh`
- Delete: `.dockerignore`

- [ ] **Step 1: Remove demo files**

```bash
git rm server.js package.json .env Dockerfile build.sh run.sh .dockerignore
```

- [ ] **Step 2: Update .gitignore**

Replace contents of `.gitignore` with:

```
data/
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "remove demo boilerplate files"
```

---

### Task 2: Create template files

**Files:**
- Create: `template/Dockerfile`
- Create: `template/.dockerignore`
- Create: `template/build.sh`
- Create: `template/run.sh`

- [ ] **Step 1: Create template/Dockerfile**

```dockerfile
FROM node:22-slim AS base
WORKDIR /app
COPY package*.json ./

# ── Dev: all deps, source mounted via volume ──
FROM base AS dev
RUN npm ci
CMD ["npm", "run", "dev"]

# ── Prod: minimal image, source baked in ──
FROM base AS prod
RUN npm ci --omit=dev
COPY . .
CMD ["node", "server.js"]
```

No placeholders — this file is generic.

- [ ] **Step 2: Create template/.dockerignore**

```
node_modules
data
.env
.git
.greenbox
*.sh
```

No placeholders — generic.

- [ ] **Step 3: Create template/build.sh**

Standalone build script. Reads `.greenbox` config at runtime — no placeholders needed.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Read config
GREENBOX_CONFIG="$(dirname "$0")/.greenbox"
if [ ! -f "$GREENBOX_CONFIG" ]; then
  echo "Error: .greenbox config not found"
  exit 1
fi
NAME=$(grep '^name=' "$GREENBOX_CONFIG" | cut -d= -f2)

TARGET="${1:-prod}"

if [ "$TARGET" = "dev" ]; then
  docker build --target dev -t "greenbox-${NAME}:dev" .
else
  docker build --target prod -t "greenbox-${NAME}:latest" .
fi
```

- [ ] **Step 4: Create template/run.sh**

Standalone run script template. Reads `.greenbox` for config. Full logic: credential check, port scan, build, stop, mount, run.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Read config
GREENBOX_CONFIG="$(dirname "$0")/.greenbox"
if [ ! -f "$GREENBOX_CONFIG" ]; then
  echo "Error: .greenbox config not found"
  exit 1
fi
NAME=$(grep '^name=' "$GREENBOX_CONFIG" | cut -d= -f2)
CONFIGURED_PORT=$(grep '^port=' "$GREENBOX_CONFIG" | cut -d= -f2)
CONFIGURED_PORT="${CONFIGURED_PORT:-3100}"

CONTAINER_NAME="greenbox-${NAME}"
DEV=false

if [ "${1:-}" = "--dev" ]; then
  DEV=true
fi

# Verify Claude credentials
CLAUDE_CREDS="$HOME/.claude_mine/.credentials.json"
if [ ! -f "$CLAUDE_CREDS" ]; then
  echo "Error: $CLAUDE_CREDS not found."
  echo "Run: greenbox setup-creds"
  exit 1
fi

# Create data dir
mkdir -p data

# Find first free host port
PORT="$CONFIGURED_PORT"
MAX_PORT=$((CONFIGURED_PORT + 20))
while lsof -iTCP:"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1; do
  ((PORT++))
  if [ "$PORT" -gt "$MAX_PORT" ]; then
    echo "Error: no free port found in range ${CONFIGURED_PORT}-${MAX_PORT}"
    exit 1
  fi
done

# Build
if [ "$DEV" = true ]; then
  docker build --target dev -t "greenbox-${NAME}:dev" .
else
  docker build --target prod -t "greenbox-${NAME}:latest" .
fi

# Stop existing container if running
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

# Env file
ENV_ARGS=()
if [ -f .env ]; then
  ENV_ARGS=(--env-file .env)
fi

# Run
if [ "$DEV" = true ]; then
  docker run -d \
    --name "$CONTAINER_NAME" \
    -p "$PORT:$CONFIGURED_PORT" \
    "${ENV_ARGS[@]+"${ENV_ARGS[@]}"}" \
    -v "$CLAUDE_CREDS:/home/node/.claude/.credentials.json:ro" \
    -v "$(pwd):/app" \
    -v "greenbox-${NAME}-node_modules:/app/node_modules" \
    -v "$(pwd)/data:/app/data" \
    "greenbox-${NAME}:dev"
else
  docker run -d \
    --name "$CONTAINER_NAME" \
    -p "$PORT:$CONFIGURED_PORT" \
    "${ENV_ARGS[@]+"${ENV_ARGS[@]}"}" \
    -v "$CLAUDE_CREDS:/home/node/.claude/.credentials.json:ro" \
    -v "$(pwd)/data:/app/data" \
    "greenbox-${NAME}:latest"
fi

echo ""
echo "Running at http://localhost:$PORT"
if [ "$DEV" = true ]; then
  echo "Mode: dev (live reload)"
fi
echo "Logs: docker logs -f $CONTAINER_NAME"
```

- [ ] **Step 5: Commit**

```bash
git add template/
git commit -m "add template files for bootstrap"
```

---

## Chunk 2: Greenbox CLI — Core and Commands

### Task 3: Create greenbox executable with helpers and usage

**Files:**
- Create: `greenbox`

- [ ] **Step 1: Create the greenbox script with usage, config reading, and command dispatch**

Create `greenbox` as an executable bash script. This step includes:
- `usage()` function — prints help for all commands, exits 1
- `read_config()` function — reads `.greenbox` from a given directory, sets `GB_NAME` and `GB_PORT` variables. Exits with error if `.greenbox` is missing.
- `resolve_dir()` function — takes an optional dir argument, defaults to `pwd`. Validates directory exists.
- Command function stubs — each prints "not implemented" and exits 1, replaced in subsequent tasks
- Command dispatch via `case` statement at the bottom

```bash
#!/usr/bin/env bash
set -euo pipefail

# ── Resolve where greenbox itself is installed (for template access) ──
GREENBOX_HOME="$(cd "$(dirname "$0")" && pwd)"

# ── Helpers ──

usage() {
  cat <<'USAGE'
Usage: greenbox <command> [options]

Commands:
  bootstrap [--standalone]    Add Dockerfile + .dockerignore to current directory
  build [--dev] [<dir>]       Build Docker image
  run [--dev] [<dir>]         Build and run container
  stop [<name>]               Stop and remove container
  list                        List greenbox containers
  logs [<name>]               Tail container logs
  setup-creds                 Set up ~/.claude_mine/ credential directory
USAGE
  exit 1
}

read_config() {
  local dir="$1"
  local config="$dir/.greenbox"
  if [ ! -f "$config" ]; then
    echo "Error: .greenbox not found in $dir"
    echo "Run: greenbox bootstrap"
    exit 1
  fi
  GB_NAME=$(grep '^name=' "$config" | cut -d= -f2)
  GB_PORT=$(grep '^port=' "$config" | cut -d= -f2)
  GB_PORT="${GB_PORT:-3100}"
  if [ -z "$GB_NAME" ]; then
    echo "Error: 'name' not set in $config"
    exit 1
  fi
}

resolve_dir() {
  local dir="${1:-$(pwd)}"
  if [ ! -d "$dir" ]; then
    echo "Error: $dir is not a directory"
    exit 1
  fi
  echo "$(cd "$dir" && pwd)"
}

# ── Command stubs (replaced in subsequent tasks) ──

cmd_bootstrap()  { echo "not implemented"; exit 1; }
cmd_build()      { echo "not implemented"; exit 1; }
cmd_run()        { echo "not implemented"; exit 1; }
cmd_stop()       { echo "not implemented"; exit 1; }
cmd_list()       { echo "not implemented"; exit 1; }
cmd_logs()       { echo "not implemented"; exit 1; }
cmd_setup_creds(){ echo "not implemented"; exit 1; }

# ── Command dispatch ──

COMMAND="${1:-}"
shift 2>/dev/null || true

case "$COMMAND" in
  bootstrap)  cmd_bootstrap "$@" ;;
  build)      cmd_build "$@" ;;
  run)        cmd_run "$@" ;;
  stop)       cmd_stop "$@" ;;
  list)       cmd_list "$@" ;;
  logs)       cmd_logs "$@" ;;
  setup-creds) cmd_setup_creds "$@" ;;
  *)          usage ;;
esac
```

Subsequent tasks replace the stub functions with real implementations. In bash, when a function is defined twice, the later definition wins.

- [ ] **Step 2: Make executable**

```bash
chmod +x greenbox
```

- [ ] **Step 3: Verify usage output**

```bash
./greenbox
```

Expected: prints usage help, exits 1.

- [ ] **Step 4: Commit**

```bash
git add greenbox
git commit -m "add greenbox executable with usage and helpers"
```

---

### Task 4: Add setup-creds command

**Files:**
- Modify: `greenbox`

- [ ] **Step 1: Add cmd_setup_creds function**

Add above the command dispatch block:

```bash
cmd_setup_creds() {
  local dir="$HOME/.claude_mine"
  local file="$dir/.credentials.json"

  mkdir -p "$dir"
  chmod 700 "$dir"

  if [ ! -f "$file" ]; then
    touch "$file"
    chmod 600 "$file"
    echo "Created $file — paste your credentials into it."
  else
    chmod 600 "$file"
    echo "$file already exists."
  fi
}
```

- [ ] **Step 2: Test**

```bash
./greenbox setup-creds
```

Expected: creates `~/.claude_mine/.credentials.json` or reports it exists.

- [ ] **Step 3: Commit**

```bash
git add greenbox
git commit -m "add setup-creds command"
```

---

### Task 5: Add bootstrap command

**Files:**
- Modify: `greenbox`

- [ ] **Step 1: Add cmd_bootstrap function**

Add above the command dispatch block. Logic:
1. Parse `--standalone` flag
2. Prompt for project name (default: basename of cwd)
3. Prompt for port (default: 3100)
4. Copy `template/Dockerfile` and `template/.dockerignore` — skip if exists
5. Write `.greenbox` config
6. Append `data/` to `.gitignore` if needed
7. If `--standalone`: copy `template/build.sh` and `template/run.sh` (they read `.greenbox` at runtime, no substitution needed)

```bash
copy_template() {
  local src="$1" dest="$2"
  if [ -f "$dest" ]; then
    echo "  Skipped $dest (already exists)"
    return
  fi
  cp "$src" "$dest"
  echo "  Created $dest"
}

cmd_bootstrap() {
  local standalone=false
  if [ "${1:-}" = "--standalone" ]; then
    standalone=true
  fi

  local default_name
  default_name=$(basename "$(pwd)")

  printf "Project name (%s): " "$default_name"
  read -r input_name
  local name="${input_name:-$default_name}"

  printf "Port (3100): "
  read -r input_port
  local port="${input_port:-3100}"

  echo ""

  # Dockerfile and .dockerignore — straight copy
  copy_template "$GREENBOX_HOME/template/Dockerfile" "Dockerfile"
  copy_template "$GREENBOX_HOME/template/.dockerignore" ".dockerignore"

  # .greenbox config
  if [ -f ".greenbox" ]; then
    echo "  Skipped .greenbox (already exists)"
  else
    printf "name=%s\nport=%s\n" "$name" "$port" > .greenbox
    echo "  Created .greenbox"
  fi

  # .gitignore — append data/ if needed
  if [ -f ".gitignore" ]; then
    if ! grep -qx 'data/' .gitignore; then
      echo 'data/' >> .gitignore
      echo "  Appended data/ to .gitignore"
    fi
  else
    echo 'data/' > .gitignore
    echo "  Created .gitignore"
  fi

  # Standalone scripts
  if [ "$standalone" = true ]; then
    if [ -f "build.sh" ]; then
      echo "  Skipped build.sh (already exists)"
    else
      cp "$GREENBOX_HOME/template/build.sh" build.sh
      chmod +x build.sh
      echo "  Created build.sh"
    fi

    if [ -f "run.sh" ]; then
      echo "  Skipped run.sh (already exists)"
    else
      cp "$GREENBOX_HOME/template/run.sh" run.sh
      chmod +x run.sh
      echo "  Created run.sh"
    fi
  fi

  echo ""
  echo "Done. Run 'greenbox run --dev .' to start."
}
```

- [ ] **Step 2: Test bootstrap in a temp directory**

```bash
mkdir /tmp/test-greenbox && cd /tmp/test-greenbox
/path/to/greenbox bootstrap
```

Expected: prompts for name/port, creates Dockerfile, .dockerignore, .greenbox, .gitignore.

- [ ] **Step 3: Test bootstrap --standalone**

```bash
mkdir /tmp/test-greenbox-sa && cd /tmp/test-greenbox-sa
/path/to/greenbox bootstrap --standalone
```

Expected: also creates build.sh and run.sh.

- [ ] **Step 4: Test skip behavior**

Run bootstrap again in same directory. Expected: all files report "Skipped".

- [ ] **Step 5: Commit**

```bash
git add greenbox
git commit -m "add bootstrap command"
```

---

### Task 6: Add build command

**Files:**
- Modify: `greenbox`

- [ ] **Step 1: Add cmd_build function**

```bash
cmd_build() {
  local dev=false
  local dir=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --dev) dev=true ;;
      *)     dir="$1" ;;
    esac
    shift
  done

  dir=$(resolve_dir "$dir")
  read_config "$dir"

  if [ "$dev" = true ]; then
    docker build --target dev -t "greenbox-${GB_NAME}:dev" "$dir"
  else
    docker build --target prod -t "greenbox-${GB_NAME}:latest" "$dir"
  fi
}
```

- [ ] **Step 2: Commit**

```bash
git add greenbox
git commit -m "add build command"
```

---

### Task 7: Add run command

**Files:**
- Modify: `greenbox`

- [ ] **Step 1: Add cmd_run function**

```bash
cmd_run() {
  local dev=false
  local dir=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --dev) dev=true ;;
      *)     dir="$1" ;;
    esac
    shift
  done

  dir=$(resolve_dir "$dir")
  read_config "$dir"

  local container_name="greenbox-${GB_NAME}"

  # Verify credentials
  local creds="$HOME/.claude_mine/.credentials.json"
  if [ ! -f "$creds" ]; then
    echo "Error: $creds not found."
    echo "Run: greenbox setup-creds"
    exit 1
  fi

  # Create data dir
  mkdir -p "$dir/data"

  # Find free port
  local port="$GB_PORT"
  local max_port=$((GB_PORT + 20))
  while lsof -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1; do
    ((port++))
    if [ "$port" -gt "$max_port" ]; then
      echo "Error: no free port in range ${GB_PORT}-${max_port}"
      exit 1
    fi
  done

  # Build
  if [ "$dev" = true ]; then
    cmd_build --dev "$dir"
  else
    cmd_build "$dir"
  fi

  # Stop existing
  docker rm -f "$container_name" 2>/dev/null || true

  # Env file
  local env_args=()
  if [ -f "$dir/.env" ]; then
    env_args=(--env-file "$dir/.env")
  fi

  # Run
  if [ "$dev" = true ]; then
    docker run -d \
      --name "$container_name" \
      -p "$port:$GB_PORT" \
      "${env_args[@]+"${env_args[@]}"}" \
      -v "$creds:/home/node/.claude/.credentials.json:ro" \
      -v "$dir:/app" \
      -v "greenbox-${GB_NAME}-node_modules:/app/node_modules" \
      -v "$dir/data:/app/data" \
      "greenbox-${GB_NAME}:dev"
  else
    docker run -d \
      --name "$container_name" \
      -p "$port:$GB_PORT" \
      "${env_args[@]+"${env_args[@]}"}" \
      -v "$creds:/home/node/.claude/.credentials.json:ro" \
      -v "$dir/data:/app/data" \
      "greenbox-${GB_NAME}:latest"
  fi

  echo ""
  echo "Running at http://localhost:$port"
  if [ "$dev" = true ]; then
    echo "Mode: dev (live reload)"
  fi
  echo "Logs: docker logs -f $container_name"
}
```

- [ ] **Step 2: Commit**

```bash
git add greenbox
git commit -m "add run command"
```

---

### Task 8: Add stop, list, and logs commands

**Files:**
- Modify: `greenbox`

- [ ] **Step 1: Add cmd_stop function**

```bash
cmd_stop() {
  local name="${1:-}"

  if [ -z "$name" ]; then
    read_config "$(pwd)"
    name="$GB_NAME"
  fi

  local container_name="greenbox-${name}"
  docker rm -f "$container_name" 2>/dev/null || true
  echo "Stopped $container_name"
}
```

- [ ] **Step 2: Add cmd_list function**

```bash
cmd_list() {
  docker ps -a \
    --filter "name=greenbox-" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}
```

- [ ] **Step 3: Add cmd_logs function**

```bash
cmd_logs() {
  local name="${1:-}"

  if [ -z "$name" ]; then
    read_config "$(pwd)"
    name="$GB_NAME"
  fi

  docker logs -f "greenbox-${name}"
}
```

- [ ] **Step 4: Commit**

```bash
git add greenbox
git commit -m "add stop, list, and logs commands"
```

---

## Chunk 3: Cleanup and README

### Task 9: Rewrite README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite README.md**

Cover:
- What greenbox is (one paragraph)
- Installation (add to PATH)
- Quick start (`greenbox setup-creds`, `cd my-project`, `greenbox bootstrap`, `greenbox run --dev`)
- Command reference (table)
- Bootstrap details (what gets created, `--standalone`)
- `.greenbox` config format
- Dev vs prod mode
- Dev notes (macOS credentials / `~/.claude_mine/` explanation)

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "rewrite README for CLI tool"
```

---

### Task 10: Final verification

- [ ] **Step 1: Verify repo structure**

```bash
ls -la
ls -la template/
```

Expected:
```
greenbox              (executable)
setup-creds.sh        (standalone script)
template/Dockerfile
template/.dockerignore
template/build.sh
template/run.sh
README.md
docs/
.gitignore
```

- [ ] **Step 2: Verify all commands respond**

```bash
./greenbox
./greenbox setup-creds
./greenbox bootstrap --help  # should work in a temp dir
./greenbox list
```

- [ ] **Step 3: End-to-end test in a temp project**

```bash
mkdir /tmp/gb-e2e && cd /tmp/gb-e2e
npm init -y
echo 'import { createServer } from "node:http"; const s = createServer((q,r) => { r.end("ok"); }); s.listen(3100);' > server.js
/path/to/greenbox bootstrap
cat .greenbox
cat Dockerfile
ls -la
```

Verify: Dockerfile, .dockerignore, .greenbox, .gitignore all present. No server.js or package.json overwritten.
