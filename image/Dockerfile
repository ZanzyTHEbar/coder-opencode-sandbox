# OpenCode sandbox for Coder: Linux + OpenCode server + tools.
# The Coder agent is started at runtime via the template's init_script (not installed in image).
# User: coder, HOME: /home/coder (mounted persistent volume in template).

ARG OPENCODE_VERSION=1.17.7
FROM ubuntu:24.04
ARG OPENCODE_VERSION=1.17.7

ENV DEBIAN_FRONTEND=noninteractive

# Base: curl/wget for agent bootstrap, git, and minimal dev tools.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    openssh-client \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# OpenCode: install from GitHub release (opencode-linux-x64.tar.gz or arm64).
RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in amd64) OC_ARCH="x64";; arm64) OC_ARCH="arm64";; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac && \
    curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-${OC_ARCH}.tar.gz" -o /tmp/oc.tgz && \
    tar -xzf /tmp/oc.tgz -C /tmp && \
    OC_BIN=$(find /tmp -maxdepth 3 -type f -name "opencode" 2>/dev/null | head -1) && \
    cp "$OC_BIN" /usr/local/bin/opencode && chmod +x /usr/local/bin/opencode && \
    rm -rf /tmp/oc.tgz /tmp/opencode*

ENV PATH="/usr/local/bin:${PATH}"
RUN opencode --version

# User coder: match the Kubernetes template's fixed UID/GID, and add to sudoers group.
RUN groupadd --gid 1001 coder && \
    useradd --uid 1001 --gid 1001 -m -s /bin/bash -d /home/coder -G sudo coder && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder && \
    chmod 0440 /etc/sudoers.d/coder && \
    chown -R 1001:1001 /home/coder

ENV HOME=/home/coder

# Skeleton for first-time volume mount (startup_script copies to $HOME if .init_done missing).
RUN mkdir -p /etc/skel/workspace && \
    echo 'export HOME=/home/coder' >> /etc/skel/.bashrc

# Default user for local docker run; Coder workspace template sets docker_container user=0:0 for volume bootstrap then agent runs as normal.
USER coder
WORKDIR /home/coder

# Default command: overridden by Terraform to run coder_agent.main.init_script.
CMD ["sh", "-c", "echo 'No init_script'; sleep infinity"]
