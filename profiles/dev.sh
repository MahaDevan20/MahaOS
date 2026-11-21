#!/usr/bin/env bash
# Development profile: containers, languages, editors, CLI tooling.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

install_profile "development (docker, podman, compilers, CLIs)" \
  docker docker-compose docker-buildx podman buildah \
  base-devel git github-cli \
  python python-pip uv nodejs npm bun rustup go jdk-openjdk \
  neovim tmux zellij ripgrep fd bat fzf eza jq yq shellcheck

# Containers are a daily-driver convenience, not a security boundary change:
# enabling them is the user's explicit choice here.
log "enabling docker/podman services"
systemctl enable --now docker.service || warn "could not enable docker.service"
usermod -aG docker "${SUDO_USER:-$USER}" 2>/dev/null || \
  warn "run 'sudo usermod -aG docker <user>' and re-login to use docker without sudo"
