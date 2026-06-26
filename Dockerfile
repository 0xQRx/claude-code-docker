FROM node:20

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Install basic development tools, iptables/ipset (firewall) and gosu (privilege drop)
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  tmux \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  gosu \
  nano \
  vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Rename the base image's default `node` user/group to `claude` (cosmetic —
# uid/gid stay 1000, home moves to /home/claude). This renames the OS account
# only; the Node.js runtime, npm, and the `node` binary are unaffected.
RUN groupmod -n claude node && \
  usermod -l claude -d /home/claude -m node

# Ensure the claude user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R claude:claude /usr/local/share

ARG USERNAME=claude

# Persist shell history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/claude/.claude && \
  chown -R claude:claude /workspace /home/claude/.claude

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.19.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Global npm config (used while installing as claude)
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin
ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano

# Clean, font-independent robbyrussell theme (installed as claude).
# Avoids Powerlevel10k's Nerd Font requirement so the prompt renders correctly
# in any terminal font (e.g. default macOS Terminal/iTerm) with no host changes.
ARG ZSH_IN_DOCKER_VERSION=1.2.1
USER claude
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
  -t robbyrussell \
  -p git \
  -p fzf \
  -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
  -a "source /usr/share/doc/fzf/examples/completion.zsh" \
  -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  -x

# Tag the prompt with (cbox) so it's obvious you're inside the sandbox.
# Quoted heredoc (<<'EOF') prevents any build-time expansion — the line is
# written verbatim and evaluated by zsh at runtime, after the theme sets PROMPT.
RUN cat >> /home/claude/.zshrc <<'EOF'
PROMPT="%{$fg_bold[yellow]%}(cbox) %{$reset_color%}$PROMPT"
EOF

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Firewall + entrypoint scripts (installed as root)
USER root
COPY init-firewall.sh /usr/local/bin/
COPY cbox-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/cbox-entrypoint.sh && \
  echo "claude ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/claude-firewall && \
  chmod 0440 /etc/sudoers.d/claude-firewall

# Devcontainer (VS Code) runs as claude and uses its own lifecycle.
# The CLI launcher (cbox) overrides --user/--entrypoint to root for UID mapping.
USER claude
