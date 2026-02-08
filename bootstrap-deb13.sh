#!/usr/bin/env bash

set -e
export DEBIAN_FRONTEND=noninteractive

# ---------- helpers ----------
log() {
  echo -e "\n>>> $1"
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
USER_CREATED=0

# ---------- actions ----------
upgrade_system() {
  log "Upgrading system"
  apt update -qq >/dev/null 2>&1
  apt -y full-upgrade >/dev/null 2>&1
}

install_qol_packages() {
  log "Installing QoL packages"
  apt install -y \
    vim \
    tree \
    curl \
    wget \
    htop \
    tmux \
    ca-certificates \
    sudo \
    bash-completion \
    unzip >/dev/null 2>&1
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

  # create Podman directories safely as root
  mkdir -p /home/$USERNAME/.config/containers
  chown -R $USERNAME:$USERNAME /home/$USERNAME/.config

  # enforce password change on first login
  chage -d 0 "$USERNAME"

  # save creds for final display
  echo "$USERNAME:$PASSWORD" > "$CREDS_FILE"
  chmod 600 "$CREDS_FILE"

  USER_CREATED=1
}

install_podman_rootless() {
  log "Installing Podman (rootless)"

  apt install -y \
    podman \
    podman-docker \
    uidmap \
    slirp4netns \
    fuse-overlayfs >/dev/null 2>&1

  if ! id "$USERNAME" >/dev/null 2>&1; then
    echo "User '$USERNAME' does not exist — create user first"
    return
  fi

  # enable lingering for rootless containers
  loginctl enable-linger "$USERNAME"
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
      5) 
        # print final credentials if user was created
        if [ $USER_CREATED -eq 1 ]; then
          USERNAME_FINAL=$(cut -d: -f1 "$CREDS_FILE")
          PASSWORD_FINAL=$(cut -d: -f2 "$CREDS_FILE")
          IP_FINAL="$IP_ADDR"
          echo -e "\n=== Login credentials ==="
          echo "Login: $USERNAME_FINAL@$IP_FINAL"
          echo "Password: $PASSWORD_FINAL"
          echo "========================\n"
        fi
        exit 0
        ;;
      *) echo "Invalid option: $opt" ;;
    esac
  done
done
