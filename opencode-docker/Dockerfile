ARG OPENCODE_VERSION=latest
FROM ubuntu:24.04
ARG OPENCODE_VERSION=latest
ARG NERD_FONT_VERSION=latest

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ansible \
    build-essential \
    ca-certificates \
    cmake \
    coreutils \
    curl \
    fontconfig \
    fzf \
    gh \
    git \
    gosu \
    jq \
    less \
    openssh-client \
    pkg-config \
    python3 \
    ripgrep \
    rsync \
    sqlite3 \
    sudo \
    unzip \
    xdg-utils \
    zoxide \
    zsh \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash && \
    ln -sf /usr/local/bin/bun /usr/local/bin/bunx

RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in amd64) OC_ARCH="x64";; arm64) OC_ARCH="arm64";; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac && \
    if [ "$OPENCODE_VERSION" = "latest" ]; then \
      OC_VERSION=$(curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest | jq -r '.tag_name | sub("^v"; "")'); \
    else \
      OC_VERSION="$OPENCODE_VERSION"; \
    fi && \
    curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${OC_VERSION}/opencode-linux-${OC_ARCH}.tar.gz" -o /tmp/oc.tgz && \
    tar -xzf /tmp/oc.tgz -C /tmp && \
    OC_BIN=$(find /tmp -maxdepth 3 -type f -name "opencode" 2>/dev/null | head -1) && \
    cp "$OC_BIN" /usr/local/bin/opencode && chmod +x /usr/local/bin/opencode && \
    rm -rf /tmp/oc.tgz /tmp/opencode*

RUN curl -fsLS https://get.chezmoi.io | sh -s -- -b /usr/local/bin && \
    if [ "$NERD_FONT_VERSION" = "latest" ]; then \
      NF_VERSION=$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | jq -r '.tag_name'); \
    else \
      NF_VERSION="$NERD_FONT_VERSION"; \
    fi && \
    mkdir -p /usr/local/share/fonts/CaskaydiaCode && \
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NF_VERSION}/CascadiaCode.zip" -o /tmp/cascadia-code.zip && \
    unzip -q /tmp/cascadia-code.zip -d /usr/local/share/fonts/CaskaydiaCode && \
    rm -f /tmp/cascadia-code.zip && \
    fc-cache -f /usr/local/share/fonts/CaskaydiaCode

ENV PATH="/usr/local/bin:${PATH}" \
    HOME=/home/coder \
    WORKSPACE_DIR=/home/coder/workspace \
    OPENCODE_UID=1800 \
    OPENCODE_GID=1800 \
    OPENCODE_HOST=0.0.0.0 \
    OPENCODE_PORT=4096

RUN opencode --version
RUN node --version && npm --version && npx --version && bun --version

RUN groupadd --gid 1800 coder && \
    useradd --uid 1800 --gid 1800 -m -s /usr/bin/zsh -d /home/coder -G sudo coder && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder && \
    chmod 0440 /etc/sudoers.d/coder && \
    mkdir -p /etc/skel/workspace && \
    echo 'export HOME=/home/coder' >> /etc/skel/.bashrc && \
    echo 'export HOME=/home/coder' >> /etc/skel/.zshrc && \
    chown -R coder:coder /home/coder

COPY scripts/entrypoint.sh /usr/local/bin/opencode-docker-entrypoint
COPY scripts/opencode-startup.sh /usr/local/bin/opencode-startup
COPY scripts/project-discovery-server.py /usr/local/bin/opencode-project-discovery-server

RUN chmod 0755 /usr/local/bin/opencode-docker-entrypoint /usr/local/bin/opencode-startup /usr/local/bin/opencode-project-discovery-server

USER root
WORKDIR /home/coder/workspace
EXPOSE 4096

ENTRYPOINT ["/usr/local/bin/opencode-docker-entrypoint"]
