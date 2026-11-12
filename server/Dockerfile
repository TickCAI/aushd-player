FROM node:22-alpine

WORKDIR /app
COPY package.json ./
COPY src ./src
COPY scripts ./scripts
COPY data ./data
RUN mkdir -p /app/artifacts && chown -R node:node /app

USER node
ENV PORT=8787 \
    DATA_DIR=/app/data \
    ARTIFACTS_DIR=/app/artifacts \
    MAX_BODY_BYTES=2097152

EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s \
  CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "src/server.js"]
