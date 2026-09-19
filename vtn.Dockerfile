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
# Cooks the SAME feature set the builder uses below: a mismatch means the cooked
# dependency cache does not match what the build needs, and it recompiles anyway.
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
    cargo chef cook --release --recipe-path recipe.json \
      --no-default-features \
      --features postgres,internal-oauth,compression-br,compression-deflate,compression-gzip,compression-zstd

# --- Stage 3: build (compile application code only) ---
# The feature list is spelled out rather than inherited, for two reasons that pull
# in opposite directions:
#
#   * `internal-oauth` is NOT a default. It gates POST /auth/token and the whole
#     /users tree, and the lab authenticates every VEN, the BFF, the seed script
#     and every BDD step through that endpoint -- without it the image builds
#     fine and then 404s on every token request.
#   * `experimental-websockets` IS a default, and is deliberately dropped.
#     Upstream's own note on it reads "object privacy is not yet implemented",
#     so what that transport delivers is not filtered the way every REST read is.
#     The lab creates no subscriptions today, so the route can deliver nothing,
#     making it a transport with no consumer (`no-half-built-features`).
#     Re-enable it deliberately, with the privacy question answered, if
#     subscriptions are adopted (design.md Q3).
#
# Everything else is upstream's default set, restated so a future upstream change
# to those defaults shows up here as a conflict rather than silently.
FROM cook AS builder
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/app/target \
    SQLX_OFFLINE=true RUSTFLAGS="-Ctarget-feature=-crt-static" \
    cargo build --release --bin openleadr-vtn \
      --no-default-features \
      --features postgres,internal-oauth,compression-br,compression-deflate,compression-gzip,compression-zstd && \
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
