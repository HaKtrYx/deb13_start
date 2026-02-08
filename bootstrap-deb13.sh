#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# Config
# ----------------------------
BASE_PKGS=(
  sudo vim tree
  curl wget git
  htop tmux
  ca-certificates gnupg
  uidmap slirp4netns fuse-overlayfs
)

# Podman + compose integration on Debian
PODMAN_PKGS=(
  podman
  podman-compose
)

PASS_LEN=16
NOPASSWD_SUDO=1

SUBID_START=100000
SUBID_COUNT=65536

# ----------------------------
# Helpers
# ----------------------------
log() { echo "[*] $*"; }
die() { echo "[!] $*" >&2; exit 1; }

require_root() {
  local euid="${EUID:-$(id -u)}"
  [[ "$euid" -eq 0 ]] || die "Run as root."
}

sanitize_username() {
  local raw="$1"
  local u

  u="$(
    echo "$raw" \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//'
  )"

  [[ -n "$u" ]] || u="user"
  [[ "$u" =~ ^[a-z] ]] || u="u-$u"

  echo "$u"
}

gen_password() {
  # Letters + digits + symbols; chpasswd-safe
  # NOTE: '-' MUST be first or last in tr set
  local pw
  while true; do
    pw="$(
      LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*_=+.?,-' </dev/urandom \
        | head -c "$PASS_LEN"
    )"

    [[ "${#pw}" -eq "$PASS_LEN" ]] || continue
    [[ "$pw" =~ [A-Z] ]] || continue
    [[ "$pw" =~ [a-z] ]] || continue
    [[ "$pw" =~ [0-9] ]] || continue
    [[ "$pw" =~ [\!\@\#\$\%\^\&\*\_\=\+\.\?,\-] ]] || continue

    printf '%s' "$pw"
    return 0
  done
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y "${BASE_PKGS[@]}" "${PODMAN_PKGS[@]}"
}

ensure_user_and_sudo() {
  local user="$1"

  if ! id -u "$user" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$user"
  fi

  usermod -aG sudo "$user"

  if [[ "$NOPASSWD_SUDO" == "1" ]]; then
    local sudoers_file="/etc/sudoers.d/$user"
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$user" > "$sudoers_file"
    chmod 0440 "$sudoers_file"
  fi
}

set_password() {
  local user="$1" pw="$2"
  printf '%s:%s\n' "$user" "$pw" | chpasswd
}

ensure_subid_range() {
  local file="$1" user="$2"
  if ! grep -qE "^${user}:" "$file" 2>/dev/null; then
    printf '%s:%s:%s\n' "$user" "$SUBID_START" "$SUBID_COUNT" >> "$file"
  fi
}

enable_rootless_podman() {
  local user="$1"

  ensure_subid_range /etc/subuid "$user"
  ensure_subid_range /etc/subgid "$user"

  if command -v loginctl >/dev/null 2>&1; then
    loginctl enable-linger "$user" >/dev/null 2>&1 || true
  fi
}

print_next_steps() {
  local user="$1"
  cat <<EOF

====================
READY
User:     ${user}
Note:     Use 'podman-compose' or 'podman compose' as you prefer.
====================

Try rootless:
  su - ${user}
  podman info
  podman run --rm quay.io/podman/hello

Compose:
  podman-compose up -d
  # or
  podman compose up -d

EOF
}

main() {
  require_root

  local host user pw
  host="$(hostname -s)"
  user="$(sanitize_username "$host")"

  log "Hostname: $host"
  log "User:     $user"

  log "Installing packages..."
  install_packages

  log "Creating/configuring user + sudo..."
  ensure_user_and_sudo "$user"

  log "Setting up rootless Podman mappings..."
  enable_rootless_podman "$user"

  log "Generating ${PASS_LEN}-char password..."
  pw="$(gen_password)"

  log "Setting password..."
  set_password "$user" "$pw"

  echo
  echo "Password: $pw"
  print_next_steps "$user"
}

main "$@"