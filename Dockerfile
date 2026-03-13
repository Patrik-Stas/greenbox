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
