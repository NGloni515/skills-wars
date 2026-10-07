# syntax=docker/dockerfile:1
FROM node:24-slim AS backend
WORKDIR /app
COPY backend/package.json backend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY backend/tsconfig.json backend/tsconfig.build.json backend/nest-cli.json ./
COPY backend/src ./src
RUN npm run build && npm prune --omit=dev

# Godot names the export by CPU (x86_64/arm64); Docker names platforms amd64/arm64.
FROM scratch AS server-amd64
COPY game/build/server/skills-wars-server.x86_64 /skills-wars-server
FROM scratch AS server-arm64
COPY game/build/server/skills-wars-server.arm64 /skills-wars-server
FROM server-${TARGETARCH} AS server

FROM node:24-slim
WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000 \
    MATCH_SERVER_COMMAND=/app/server/skills-wars-server \
    MATCH_SERVER_ARGS=--headless
COPY --from=backend /app/package.json ./
COPY --from=backend /app/node_modules ./node_modules
COPY --from=backend /app/dist ./dist
COPY --from=server /skills-wars-server ./server/skills-wars-server
USER node
EXPOSE 3000/tcp 7800-7819/udp
HEALTHCHECK --interval=30s --timeout=3s \
  CMD node -e "fetch('http://127.0.0.1:3000/health').then((r) => process.exit(r.ok ? 0 : 1), () => process.exit(1))"
CMD ["node", "dist/main.js"]
