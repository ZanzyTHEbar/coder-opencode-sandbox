# External-user OpenCode base image. No tenant secrets are baked in.

FROM ubuntu:24.04
ARG OPENCODE_VERSION=1.17.7
ARG OPENCODE_SHA256

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    fzf \
    git \
    gh \
    jq \
    less \
    openssh-client \
    pkg-config \
    ripgrep \
    sqlite3 \
    sudo \
    unzip \
    xdg-utils \
    zoxide \
    && rm -rf /var/lib/apt/lists/*

RUN test -n "$OPENCODE_SHA256" && \
    ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in amd64) OC_ARCH="x64";; arm64) OC_ARCH="arm64";; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac && \
    curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-${OC_ARCH}.tar.gz" -o /tmp/opencode.tgz && \
    printf '%s  /tmp/opencode.tgz\n' "$OPENCODE_SHA256" | sha256sum -c - && \
    tar -xzf /tmp/opencode.tgz -C /tmp && \
    OC_BIN_COUNT=$(find /tmp -maxdepth 3 -type f -name opencode | wc -l) && \
    test "$OC_BIN_COUNT" = "1" && \
    OC_BIN=$(find /tmp -maxdepth 3 -type f -name opencode) && \
    cp "$OC_BIN" /usr/local/bin/opencode && \
    chmod +x /usr/local/bin/opencode && \
    rm -rf /tmp/opencode.tgz /tmp/opencode*

RUN groupadd --gid 1800 coder && \
    useradd --uid 1800 --gid 1800 --create-home --shell /bin/bash coder && \
    mkdir -p /home/coder/workspace /home/coder/.opencode && \
    chown -R coder:coder /home/coder

USER 1800:1800
ENV HOME=/home/coder PATH="/usr/local/bin:${PATH}"
WORKDIR /home/coder/workspace

RUN opencode --version

CMD ["sh", "-lc", "opencode web --hostname 127.0.0.1 --port 4096 --cwd /home/coder/workspace"]
