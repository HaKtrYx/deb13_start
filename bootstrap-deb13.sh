#!/usr/bin/env bash

set -e
export DEBIAN_FRONTEND=noninteractive

# ---------- helpers ----------
log() {
  echo -e "\n>>> $1"
}

pause() {
  read -rp "Press Enter to continue..."
}

require_root() {
  if [ "$EUID" -ne 0 ]; then
    echo "Run as root (sudo)"
    exit 1
  fi
}

# ---------- globals ----------
USERNAME="$(hostname)"
IP_ADDR="$(hostname -I | awk '{print $1}')"
CREDS_FILE="/root/initial_credentials.txt"

# ---------- actions ----------
upgrade_system() {
  log "Upgrading system"
  apt update -qq
  apt -y -qq full-upgrade
}

install_qol_packages() {
  log "Installing QoL packages"

  apt install -y -qq \
    vim \
    tree \
    curl \
    wget \
    htop \
    tmux \
    ca-certificates \
    sudo \
    bash-completion \
    unzip
}

create_user() {
  log "Creating user from hostname"

  if id "$USERNAME" >/dev/null 2>&1; then
    echo "User '$USERNAME' already exists"
    return
  fi

  PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"

  useradd -m -s /bin/bash "$USERNAME"
  echo "$USERNAME:$PASSWORD" | chpasswd
  usermod -aG sudo "$USERNAME"

  chage -d 0 "$USERNAME"

  echo "User created:"
  echo "  Login: $USERNAME@$IP_ADDR"
  echo "  Password: $PASSWORD"

  {
    echo "Login: $USERNAME@$IP_ADDR"
    echo "Password: $PASSWORD"
    echo
  } >> "$CREDS_FILE"

  chmod 600 "$CREDS_FILE"
}

install_podman_rootless() {
  log "Installing Podman (rootless)"

  apt install -y -qq \
    podman \
    podman-docker \
    uidmap \
    slirp4netns \
    fuse-overlayfs

  if ! id "$USERNAME" >/dev/null 2>&1; then
    echo "User '$USERNAME' does not exist — create user first"
    return
  fi

  loginctl enable-linger "$USERNAME"

  su - "$USERNAME" -c "mkdir -p ~/.config/containers"

  echo "Rootless Podman ready"
  echo "Test after login:"
  echo "  podman run --rm hello-world"
}

# ---------- menu ----------
show_menu() {
  clear
  echo "=== Debian 13 Bootstrap Menu ==="
  echo
  echo "1) Upgrade system"
  echo "2) Install QoL packages"
  echo "3) Create user (hostname-based)"
  echo "4) Install Podman (rootless)"
  echo "5) Exit"
  echo
}

# ---------- main ----------
require_root

while true; do
  show_menu
  read -rp "Select option (e.g. 1 or 1 4): " choice

  for opt in $choice; do
    case "$opt" in
      1) upgrade_system ;;
      2) install_qol_packages ;;
      3) create_user ;;
      4) install_podman_rootless ;;
      5) exit 0 ;;
      *) echo "Invalid option: $opt" ;;
    esac
  done

  pause
done
