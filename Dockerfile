# Build stage
FROM node:22.9-bookworm as build

WORKDIR /app
COPY package.json package-lock.json ./
RUN \
    npm ci --omit=dev && \
    npm cache clean --force

# Compile stage
FROM node:22.9-bookworm as compile

WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
COPY src/ src/
RUN \
    npm ci && \
    npm cache clean --force && \
    npm run build

# Release stage
FROM node:22.9-bookworm-slim AS release

ARG APP_NAME
ARG APP_VERSION
ARG APP_REVISION

ARG APP_USER=app
ARG APP_UID=1000
ARG APP_GROUP=app
ARG APP_GID=2000

LABEL \
    org.opencontainers.image.title=${APP_NAME} \
    org.opencontainers.image.version=${APP_VERSION} \
    org.opencontainers.image.revision=${APP_REVISION}

RUN \
    apt-get update && \
    apt-get -y upgrade && \
    DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
        dumb-init=1.2.5-2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    deluser node && \
    addgroup --system --gid ${APP_GID} --no-create-home ${APP_GROUP} && \
    adduser --system \
        --uid ${APP_UID} \
        --ingroup ${APP_GROUP} \
        --disabled-password \
        --gecos "" ${APP_USER} && \
    chmod -R ug-s /bin /sbin /usr/bin && \
    rm -rf /tmp/*

WORKDIR /app
COPY --from=build --chown=root:app --chmod=640 /app/node_modules node_modules
COPY --from=build --chown=root:app --chmod=640 \
    /app/package.json /app/package-lock.json ./
COPY --from=compile --chown=root:app --chmod=640 /app/dist ./
RUN chmod -R ug+x /app

ENV NODE_ENV=production

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "/app/app.js"]

USER ${APP_UID}
