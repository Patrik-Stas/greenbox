FROM node:22-bookworm AS base
WORKDIR /app

RUN mkdir -p /home/node/.claude \
    && chown -R node:node /app /home/node/.claude

USER node

RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/node/.local/bin:${PATH}"

COPY --chown=node:node package*.json ./

# ── Dev: all deps, source mounted via volume ──
FROM base AS dev
RUN npm ci
CMD ["npm", "run", "dev"]

# ── Prod: minimal image, source baked in ──
FROM base AS prod
RUN npm ci --omit=dev
COPY --chown=node:node . .
CMD ["npm", "start"]
