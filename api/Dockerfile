# syntax=docker/dockerfile:1

# ---------- Stage 1: install production dependencies ----------
FROM node:26-alpine AS deps

WORKDIR /app

# Manifests are copied on their own, before any source, so this layer is
# only invalidated when the dependency set actually changes. Editing
# server.js then rebuilds without re-downloading a single package.
COPY package.json package-lock.json ./

# npm ci installs exactly what the lockfile pins (reproducible, and it
# fails loudly if the lockfile and package.json have drifted), unlike
# npm install which may silently resolve newer versions and rewrite the
# lockfile. --omit=dev keeps devDependencies out of the runtime image.
RUN npm ci --omit=dev

# ---------- Stage 2: runtime ----------
FROM node:26-alpine AS runtime

ENV NODE_ENV=production

WORKDIR /app

# node:alpine already ships an unprivileged "node" user (uid/gid 1000),
# so there is no need to create one. Copy in as that user rather than
# copying as root and chown-ing afterwards, which would double the layer.
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node server.js ./

# Everything after this point runs unprivileged.
USER node

# server.js falls back to 4000 when PORT is unset; the real value comes
# from the environment (see .env.example), not from the image.
EXPOSE 4000

# Uses the node binary that is already present rather than installing
# curl/wget, so the healthcheck adds nothing to the image or its attack
# surface. Exec form avoids spawning a shell on every probe.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:' + (process.env.PORT || 4000) + '/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"]

CMD ["node", "server.js"]
