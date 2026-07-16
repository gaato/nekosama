FROM debian:bookworm-slim AS build

ARG MOONBIT_VERSION=0.10.4+2cc641edf

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        libssl-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl --fail --silent --show-error --location \
        https://cli.moonbitlang.com/install/unix.sh \
        --output /tmp/moonbit-install.sh \
    && bash /tmp/moonbit-install.sh "${MOONBIT_VERSION}" \
    && rm /tmp/moonbit-install.sh

ENV PATH="/root/.moon/bin:${PATH}"

WORKDIR /app

COPY . .

RUN moon update \
    && moon build --release --target native

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build \
    /app/_build/native/release/build/gaato/nekosama/main/main.exe \
    /usr/local/bin/nekosama

USER nobody

ENTRYPOINT ["/usr/local/bin/nekosama"]
