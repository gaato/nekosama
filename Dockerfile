FROM ghcr.io/gaato/moonbit:0.10.14-7d59c7ec9 AS build

# TLS and zlib headers for the native backend, and Node.js for the
# gaato/discord prebuild script.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        libssl-dev \
        nodejs \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

COPY . .

RUN moon update \
    && moon build --release --target native

# The binary links against the builder's glibc (Debian 13), so the runtime
# must be Debian 13 as well.
FROM debian:trixie-slim AS runtime

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        libssl3t64 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build \
    /work/_build/native/release/build/main/main.exe \
    /usr/local/bin/nekosama

# Per-guild settings and feature state live here; mount a volume to keep them.
ENV NEKOSAMA_DATA_DIR=/data
RUN mkdir /data && chown nobody /data
VOLUME /data

USER nobody

ENTRYPOINT ["/usr/local/bin/nekosama"]
