# syntax=docker/dockerfile:1
FROM swift:6.1.3-bookworm@sha256:20daec1d4e4531c8bc61dd8c41c63c4ec27159d1549318bdba57e3b93e3edf75
RUN --mount=type=secret,id=proxy_ca \
    apt-get -o Acquire::https::CaInfo=/run/secrets/proxy_ca update \
    && apt-get -o Acquire::https::CaInfo=/run/secrets/proxy_ca install -y --no-install-recommends libssl-dev libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app/Packages/ChaiTradeCore
CMD ["swift", "test"]
