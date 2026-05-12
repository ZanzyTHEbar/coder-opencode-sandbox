ARG OPENCODE_VERSION=1.14.29
FROM ubuntu:24.04
ARG OPENCODE_VERSION=1.14.29

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    coreutils \
    curl \
    git \
    gosu \
    jq \
    openssh-client \
    sudo \
    && rm -rf /var/lib/apt/lists/*

RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in amd64) OC_ARCH="x64";; arm64) OC_ARCH="arm64";; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac && \
    curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-${OC_ARCH}.tar.gz" -o /tmp/oc.tgz && \
    tar -xzf /tmp/oc.tgz -C /tmp && \
    OC_BIN=$(find /tmp -maxdepth 3 -type f -name "opencode" 2>/dev/null | head -1) && \
    cp "$OC_BIN" /usr/local/bin/opencode && chmod +x /usr/local/bin/opencode && \
    rm -rf /tmp/oc.tgz /tmp/opencode*

ENV PATH="/usr/local/bin:${PATH}" \
    HOME=/home/coder \
    WORKSPACE_DIR=/home/coder/workspace \
    OPENCODE_UID=1800 \
    OPENCODE_GID=1800 \
    OPENCODE_HOST=0.0.0.0 \
    OPENCODE_PORT=4096

RUN opencode --version

RUN groupadd --gid 1800 coder && \
    useradd --uid 1800 --gid 1800 -m -s /bin/bash -d /home/coder -G sudo coder && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder && \
    chmod 0440 /etc/sudoers.d/coder && \
    mkdir -p /etc/skel/workspace && \
    echo 'export HOME=/home/coder' >> /etc/skel/.bashrc && \
    chown -R coder:coder /home/coder

COPY scripts/entrypoint.sh /usr/local/bin/opencode-docker-entrypoint
COPY scripts/opencode-startup.sh /usr/local/bin/opencode-startup

RUN chmod 0755 /usr/local/bin/opencode-docker-entrypoint /usr/local/bin/opencode-startup

USER root
WORKDIR /home/coder
EXPOSE 4096

ENTRYPOINT ["/usr/local/bin/opencode-docker-entrypoint"]
