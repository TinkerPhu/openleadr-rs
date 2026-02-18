FROM rust:1.90-alpine AS base

# Install build dependencies
RUN apk add --no-cache alpine-sdk openssl-dev openssl-libs-static

# --- Stage 1: planner (extract dependency recipe) ---
FROM base AS planner
RUN cargo install cargo-chef
WORKDIR /app
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

# --- Stage 2: cook (compile dependencies only) ---
# Two-layer caching strategy:
#   * cargo-chef layer cache: hits when Cargo.toml/Cargo.lock unchanged (fast path)
#   * BuildKit cache mounts: warm cargo cache even on layer-cache miss (source-only change)
FROM base AS cook
RUN cargo install cargo-chef
WORKDIR /app
COPY --from=planner /app/recipe.json recipe.json
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/app/target \
    SQLX_OFFLINE=true cargo chef cook --release --recipe-path recipe.json

# --- Stage 3: build (compile application code only) ---
FROM cook AS builder
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/app/target \
    SQLX_OFFLINE=true cargo build --release --bin openleadr-vtn && \
    cp target/release/openleadr-vtn /openleadr-vtn

# --- Stage 4: minimal runtime image ---
FROM alpine:latest AS final

# Install OpenSSL
RUN apk add --no-cache openssl-libs-static curl

# create a non root user to run the binary
ARG user=nonroot
ARG group=nonroot
ARG uid=2000
ARG gid=2000
RUN addgroup -g ${gid} ${group} && \
    adduser -u ${uid} -G ${group} -s /bin/sh -D ${user}

EXPOSE 3000

WORKDIR /dist

COPY --from=builder --chown=nonroot:nonroot /openleadr-vtn /dist/openleadr-vtn
RUN chmod 777 /dist/openleadr-vtn

USER $user

ENTRYPOINT ["/dist/openleadr-vtn"]
