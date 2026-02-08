#!/usr/bin/env bash
set -euo pipefail

# ---------- Settings ----------
# Baseline packages you want everywhere
BASE_PKGS=(
  sudo vim tree
  curl wget git
  htop tmux
  ca-certificates gnupg lsb-release
)

# Docker packages (installed from Docker's official repo)
DOCKER_PKGS=(
  docker-ce docker-ce-cli containerd.io
  docker-buildx-plugin docker-compose-plugin
)

# Password policy
PASS_LEN=16

# If you want sudo without password (recommended for lab boxes)
NOPASSWD_SUDO=1
# ----------------------------

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Run as root (or with sudo)." >&2
    exit 1
  fi
}

sanitize_username() {
  # Convert hostname to a safe Linux username:
  # - lowercase
  # - keep a-z 0-9 -
  # - replace others with -
  # - ensure starts with a letter
  local raw="$1"
  local u
  u="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//')"
  [[ -z "$u" ]] && u="user"
  [[ "$u" =~ ^[a-z] ]] || u="u-$u"
  echo "$u"
}

install_base_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y "${BASE_PKGS[@]}"
}

install_docker() {
  # Docker official repo (works for Debian 13 / trixie)
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  local arch codename
  arch="$(dpkg --print-architecture)"
  codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

  cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${codename} stable
EOF

  apt-get update
  apt-get install -y "${DOCKER_PKGS[@]}"
}

gen_password() {
  # Generate a random password with letters+numbers+symbols.
  # We try hard to include at least 1 of each class.
  # Uses /dev/urandom + basic filtering (no external deps).
  local pw

  while true; do
    pw="$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^_+=-.,:?' </dev/urandom | head -c "${PASS_LEN}")"
    [[ "${#pw}" -ne "${PASS_LEN}" ]] && continue
    [[ "$pw" =~ [A-Z] ]] || continue
    [[ "$pw" =~ [a-z] ]] || continue
    [[ "$pw" =~ [0-9] ]] || continue
    [[ "$pw" =~ [\!\@\#\%\^\_\+\=\-\,\.\:\?] ]] || continue
    echo "$pw"
    return 0
  done
}

ensure_user_and_sudo() {
  local user="$1"

  if ! id -u "$user" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$user"
  fi

  usermod -aG sudo "$user"

  if [[ "$NOPASSWD_SUDO" == "1" ]]; then
    echo "$user ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$user"
    chmod 440 "/etc/sudoers.d/$user"
  fi

  # Add to docker group if present
  if getent group docker >/dev/null 2>&1; then
    usermod -aG docker "$user"
  fi
}

set_user_password() {
  local user="$1"
  local pw="$2"

  # chpasswd is robust for special chars
  echo "${user}:${pw}" | chpasswd
}

main() {
  require_root

  local host user pw
  host="$(hostname -s)"
  user="$(sanitize_username "$host")"

  echo "[*] Hostname:  $host"
  echo "[*] Username:  $user"

  echo "[*] Installing baseline packages..."
  install_base_packages

  echo "[*] Installing Docker (official repo)..."
  install_docker

  echo "[*] Creating/configuring user + sudo + docker group..."
  ensure_user_and_sudo "$user"

  echo "[*] Generating random ${PASS_LEN}-char password (letters+numbers+symbols)..."
  pw="$(gen_password)"

  echo "[*] Setting password for ${user}..."
  set_user_password "$user" "$pw"

  echo
  echo "===================="
  echo "READY"
  echo "User:     ${user}"
  echo "Password: ${pw}"
  echo "===================="
  echo
  echo "Notes for Docker in LXC:"
  echo "  In Proxmox host run: pct set <CTID> -features nesting=1,keyctl=1"
  echo "  Then reboot the CT."
}

main "$@"
