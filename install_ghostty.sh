#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

sudo apt-get update
sudo apt-get install -y build-essential curl libbz2-dev libonig-dev libxml2-utils gettext libadwaita-1-dev libgtk-4-dev

ZIG_BIN="$(command -v zig 2>/dev/null || true)"
if [ -z "$ZIG_BIN" ] && [ -x /snap/bin/zig ]; then
  ZIG_BIN="/snap/bin/zig"
fi
if [ -z "$ZIG_BIN" ]; then
  printf '%s\n' "zig not found. Install zig (or snap zig) and rerun install_ghostty.sh." >&2
  exit 1
fi

sudo mkdir -p /opt/ghostty/build/ && sudo chown "$USER" /opt/ghostty/build/
"$ZIG_BIN" build -p /opt/ghostty -Doptimize=ReleaseFast -Di18n=false -fno-sys=gtk4-layer-shell --cache-dir /opt/ghostty/build/ghostty-zig-cache --global-cache-dir /opt/ghostty/build/ghostty-zig-global-cache

# Make bundled shared libs discoverable at runtime.
if ! grep -qxF "/opt/ghostty/lib" /etc/ld.so.conf.d/ghostty.conf 2>/dev/null; then
  printf '%s\n' "/opt/ghostty/lib" | sudo tee /etc/ld.so.conf.d/ghostty.conf >/dev/null
fi
sudo ldconfig

XTERM_TARGET="/opt/ghostty/bin/ghostty"
if grep -qi microsoft /proc/version 2>/dev/null; then
  cat > /tmp/ghostty-xterminal <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"
export GDK_BACKEND="${GDK_BACKEND:-wayland}"

exec /opt/ghostty/bin/ghostty --window-vsync=false --gtk-single-instance=false --async-backend=epoll --shell-integration=none "$@"
EOF
  sudo install -Dm755 /tmp/ghostty-xterminal /opt/ghostty/bin/ghostty-xterminal
  rm -f /tmp/ghostty-xterminal
  XTERM_TARGET="/opt/ghostty/bin/ghostty-xterminal"
fi

sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$XTERM_TARGET" 100
sudo update-alternatives --set x-terminal-emulator "$XTERM_TARGET"

install -Dm644 "$SCRIPT_DIR/ghostty-config.ghostty" "$HOME/.config/ghostty/config"

# Prevent literal "~200"/"~201" showing up at paste start/end in readline apps
# by explicitly enabling bracketed paste mode for bash/readline.
INPUTRC="$HOME/.inputrc"
if [ ! -f "$INPUTRC" ]; then
  touch "$INPUTRC"
fi

if ! grep -qxF "set enable-bracketed-paste on" "$INPUTRC"; then
  {
    printf '\n'
    printf '# Keep bracketed paste enabled so pasted text is wrapped safely.\n'
    printf '# Without this, some sessions can leak control markers like "~200".\n'
    printf 'set enable-bracketed-paste on\n'
  } >> "$INPUTRC"
fi
