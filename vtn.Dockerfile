FROM rust:1.90-alpine AS base

# Install build dependencies
RUN apk add --no-cache alpine-sdk openssl-dev openssl-libs-static

FROM base AS builder

WORKDIR /app
COPY . .

# BuildKit cache mounts keep ~/.cargo and target/ across rebuilds.
# Only changed crates are recompiled when source files change.
# Don't depend on live sqlx during build — use cached .sqlx
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/app/target \
    SQLX_OFFLINE=true cargo build --release --bin openleadr-vtn && \
    cp target/release/openleadr-vtn /openleadr-vtn

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
