#!/usr/bin/env bash
set -euo pipefail

# ---- baseline tools ----
BASE_PKGS=(
  sudo vim tree
  curl wget git
  htop tmux
  ca-certificates gnupg
)

# ---- docker pkgs (includes compose plugin) ----
DOCKER_PKGS=(
  docker-ce docker-ce-cli containerd.io
  docker-buildx-plugin docker-compose-plugin
)

PASS_LEN=16
NOPASSWD_SUDO=1

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Run as root." >&2
    exit 1
  fi
}

sanitize_username() {
  # username based on hostname, safe for Linux useradd
  local raw="$1"
  local u
  u="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//')"
  [[ -z "$u" ]] && u="user"
  [[ "$u" =~ ^[a-z] ]] || u="u-$u"
  echo "$u"
}

gen_password() {
  # Letters + digits + symbols, exclude ':' and whitespace (chpasswd-safe)
  # Try until it contains at least 1 upper, 1 lower, 1 digit, 1 symbol.
  local pw
  while true; do
    pw="$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*_-+=.?,' </dev/urandom | head -c "${PASS_LEN}")"
    [[ "${#pw}" -ne "${PASS_LEN}" ]] && continue
    [[ "$pw" =~ [A-Z] ]] || continue
    [[ "$pw" =~ [a-z] ]] || continue
    [[ "$pw" =~ [0-9] ]] || continue
    [[ "$pw" =~ [\!\@\#\$\%\^\&\*\_\-\+\=\.\?,] ]] || continue
    printf '%s' "$pw"
    return 0
  done
}

install_base() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y "${BASE_PKGS[@]}"
}

install_docker_official() {
  # Official Docker repo for Debian (Debian 13 / trixie supported)  [oai_citation:2‡Docker Documentation](https://docs.docker.com/engine/install/debian/?utm_source=chatgpt.com)
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  fi

  local arch codename
  arch="$(dpkg --print-architecture)"
  codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

  cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${codename} stable
EOF

  apt-get update
  apt-get install -y "${DOCKER_PKGS[@]}"
}

ensure_user() {
  local user="$1"

  if ! id -u "$user" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "$user"
  fi

  usermod -aG sudo "$user"

  if [[ "$NOPASSWD_SUDO" == "1"