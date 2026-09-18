FROM rust:1.94-alpine AS base

# Build dependencies. openssl3-dev + libgcc (rather than openssl-libs-static) because
# the release build links OpenSSL dynamically -- see RUSTFLAGS below.
RUN apk add --no-cache cmake g++ make openssl3-dev libgcc

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
    SQLX_OFFLINE=true RUSTFLAGS="-Ctarget-feature=-crt-static" \
    cargo chef cook --release --recipe-path recipe.json

# --- Stage 3: build (compile application code only) ---
# `internal-oauth` is NOT in the crate's default features: it gates POST /auth/token
# and the whole /users tree. The lab authenticates every VEN, the BFF, the seed script
# and all BDD steps through that endpoint, so the flag is mandatory here -- without it
# the image builds fine and then 404s on every token request.
FROM cook AS builder
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/app/target \
    SQLX_OFFLINE=true RUSTFLAGS="-Ctarget-feature=-crt-static" \
    cargo build --release --bin openleadr-vtn --features internal-oauth && \
    cp target/release/openleadr-vtn /openleadr-vtn

# --- Stage 4: minimal runtime image ---
FROM alpine:latest AS final

RUN apk add --no-cache libssl3 libgcc

# create a non root user to run the binary
ARG user=nonroot
ARG group=nonroot
ARG uid=2000
ARG gid=2000
RUN addgroup -g ${gid} ${group} && \
    adduser -u ${uid} -G ${group} -s /bin/sh -D ${user}

EXPOSE 3000

WORKDIR /dist

COPY --from=builder --chown=root:root --chmod=755 /openleadr-vtn /dist/openleadr-vtn

USER $user

ENTRYPOINT ["/dist/openleadr-vtn"]
