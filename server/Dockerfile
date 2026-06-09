# crafty-push — companion push server for CraftyMobile.
# Pure Node.js, no npm dependencies, so the image is tiny and has no install step.
FROM node:22-alpine

WORKDIR /app

# Only the runtime files (see .dockerignore for what's excluded).
COPY package.json crafty-push.js ./

# Device tokens are persisted here; mount a volume at /data to keep them across
# restarts. Configured via env so it works without editing the code.
ENV TOKENS_FILE=/data/tokens.json
RUN mkdir -p /data && chown -R node:node /data
USER node

# Default port (override with -e PORT=...; keep the healthcheck in sync if you do).
EXPOSE 8099

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8099/health || exit 1

CMD ["node", "crafty-push.js"]
