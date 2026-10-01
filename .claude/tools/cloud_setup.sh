#!/usr/bin/env bash
# Cloud-session bootstrap: installs Godot (Linux, console-capable) and imports solatro + worldgen.
# Idempotent. Usage: bash .claude/tools/cloud_setup.sh   then   source /opt/godot/env.sh
# Godot 4.7.2 is the pinned project version (config/features); bump VER only with the project.
set -euo pipefail
VER=4.7.2
DIR=/opt/godot
BIN=$DIR/Godot_v${VER}-stable_linux.x86_64
ROOT=$(cd "$(dirname "$0")/../.." && pwd)

if [ ! -x "$BIN" ]; then
  mkdir -p "$DIR"
  curl -sSL -o "$DIR/g.zip" "https://github.com/godotengine/godot/releases/download/${VER}-stable/Godot_v${VER}-stable_linux.x86_64.zip"
  unzip -oq "$DIR/g.zip" -d "$DIR" && rm "$DIR/g.zip"
  chmod +x "$BIN"
fi

# Xvfb and Mesa llvmpipe are preinstalled; install only if a fresh image lacks them.
command -v xvfb-run >/dev/null || { apt-get update -qq && apt-get install -y -qq xvfb libgl1-mesa-dri; }

# Godot has no headless GPU: every scene runs windowed on a virtual display (software GL).
cat > "$DIR/env.sh" <<EOF
export GODOT_BIN=$BIN
godot() { xvfb-run -a -s "-screen 0 1920x1080x24" "$BIN" "\$@"; }
EOF

for p in solatro worldgen; do
  xvfb-run -a "$BIN" --path "$ROOT/$p" --import >/dev/null 2>&1 || true
done
echo "godot ready: $("$BIN" --version)  (source $DIR/env.sh for the 'godot' wrapper)"
