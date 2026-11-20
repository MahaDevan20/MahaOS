#!/usr/bin/env bash
# AI profile: local model runtime (Ollama) and useful CPU tooling.
# Model weights are NOT bundled anywhere: they are large and must be an explicit
# user download (blueprint §6: never include model weights in the ISO).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

echo "Ollama models are several GB each. This profile installs the runtime only."
install_profile "ai (ollama runtime, no models)" \
  ollama python-pip

log "enabling ollama"
systemctl enable --now ollama.service || warn "could not enable ollama.service"

cat <<'EOF'

Next steps (each downloads model weights, mind the disk):
    ollama pull llama3.2          # ~2 GB
    ollama pull qwen2.5-coder:7b  # ~4.7 GB

Check free space first:  df -h /var/lib/ollama
EOF
