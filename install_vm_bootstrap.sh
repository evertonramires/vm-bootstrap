#!/bin/bash
set -Eeuo pipefail

# ------------------------------------------------------------
# VM BOOTSTRAP FOR AI AGENT VMS
# Debian 13 — run as root: sudo bash install_vm_bootstrap.sh
# ------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run as root (sudo bash $0)"
    exit 1
fi

# ------------------------------------------------------------
# Determine target user
# ------------------------------------------------------------

if [ -n "${VM_USER:-}" ]; then
    USER_NAME="$VM_USER"
elif [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    USER_NAME="$SUDO_USER"
else
    USER_NAME="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "nobody" && $7 !~ /(nologin|false)$/ {print $1; exit}')"
fi

if [ -z "${USER_NAME:-}" ]; then
    echo "ERROR: Could not determine the target user."
    echo "Run with VM_USER=username."
    exit 1
fi

USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
USER_GROUP="$(id -gn "$USER_NAME")"

if [ -z "$USER_HOME" ]; then
    echo "ERROR: Could not determine home directory for $USER_NAME."
    exit 1
fi

run_as_user() {
    runuser -u "$USER_NAME" -- "$@"
}

# ------------------------------------------------------------
# Base system
# ------------------------------------------------------------

echo
echo "==> Updating Debian"
apt-get update
apt-get upgrade -y

echo
echo "==> Installing packages"
apt-get install -y \
    ca-certificates \
    git \
    gh \
    curl \
    jq \
    ripgrep \
    fd-find \
    tmux \
    btop \
    net-tools \
    openssh-client \
    openssh-server \
    sudo \
    passwd \
    build-essential \
    python3 \
    nodejs \
    npm

# Debian calls the binary fdfind.
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    ln -sf /usr/bin/fdfind /usr/local/bin/fd
fi

# ------------------------------------------------------------
# Passwordless sudo
# ------------------------------------------------------------

echo
echo "==> Configuring passwordless sudo"

usermod -aG sudo "$USER_NAME"

SUDOERS_FILE="/etc/sudoers.d/$USER_NAME"

printf '%s\n' \
    "$USER_NAME ALL=(ALL:ALL) NOPASSWD:ALL" |
    tee "$SUDOERS_FILE" >/dev/null

chmod 440 "$SUDOERS_FILE"
visudo -cf "$SUDOERS_FILE"

# ------------------------------------------------------------
# uv
# ------------------------------------------------------------

echo
echo "==> Installing uv"

TMP_UV="$(mktemp)"

curl -fsSL https://astral.sh/uv/install.sh -o "$TMP_UV"
chmod 0644 "$TMP_UV"

run_as_user env \
    HOME="$USER_HOME" \
    UV_INSTALL_DIR="$USER_HOME/.local/bin" \
    sh "$TMP_UV"

rm -f "$TMP_UV"

# Ensure .local/bin is in bash PATH.
BASHRC="$USER_HOME/.bashrc"

if ! grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "$BASHRC" 2>/dev/null; then
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' |
        tee -a "$BASHRC" >/dev/null
fi

chown "$USER_NAME:$USER_GROUP" "$BASHRC"

# ------------------------------------------------------------
# kubectl
# ------------------------------------------------------------

echo
echo "==> Installing kubectl"

ARCH="$(dpkg --print-architecture)"

case "$ARCH" in
    amd64) KUBECTL_ARCH="amd64" ;;
    arm64) KUBECTL_ARCH="arm64" ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}"

TMP_KUBECTL="$(mktemp -d)"

curl -fsSL -o "$TMP_KUBECTL/kubectl" \
    "$KUBECTL_URL/kubectl"

curl -fsSL -o "$TMP_KUBECTL/kubectl.sha256" \
    "$KUBECTL_URL/kubectl.sha256"

(
    cd "$TMP_KUBECTL"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
)

install -o root -g root -m 0755 \
    "$TMP_KUBECTL/kubectl" /usr/local/bin/kubectl

rm -rf "$TMP_KUBECTL"

# ------------------------------------------------------------
# SSH
# ------------------------------------------------------------

echo
echo "==> Enabling SSH"

systemctl enable --now ssh

# Get the VM's primary IP for scp commands
VM_IP="$(ip -4 addr show | awk '/inet / && $NF != "lo" {print $2; exit}')"
if [ -z "$VM_IP" ]; then
    VM_IP="<VM-IP>"
fi

# Prepare .ssh dir (key will be added via scp)
install -d -m 700 \
    -o "$USER_NAME" -g "$USER_GROUP" \
    "$USER_HOME/.ssh"

touch "$USER_HOME/.ssh/authorized_keys"
chown "$USER_NAME:$USER_GROUP" "$USER_HOME/.ssh/authorized_keys"
chmod 600 "$USER_HOME/.ssh/authorized_keys"

# Prepare .kube dir (config will be added via scp)
install -d -m 700 \
    -o "$USER_NAME" -g "$USER_GROUP" \
    "$USER_HOME/.kube"

# ------------------------------------------------------------
# Final verification
# ------------------------------------------------------------

echo
echo "==> Verifying installation"

echo
echo "Versions:"
echo "  git:      $(git --version)"
echo "  gh:       $(gh --version | head -n1)"
echo "  python:   $(python3 --version)"
echo "  node:     $(node --version)"
echo "  npm:      $(npm --version)"
echo "  kubectl:  $(kubectl version --client --output=yaml 2>/dev/null | awk '/gitVersion:/ {print $2; exit}')"
echo "  uv:       $(run_as_user "$USER_HOME/.local/bin/uv" --version 2>/dev/null || echo installed)"

echo
echo "========================================"
echo "VM READY"
echo "========================================"
echo
echo "User: $USER_NAME"
echo "Home: $USER_HOME"
echo "Sudo: passwordless"
echo "SSH: enabled"
echo
echo "IPv4 addresses:"
ip -4 addr show |
    awk '/inet / && $NF != "lo" {
        printf "  %-18s %s\n", $2, $NF
    }'

echo
echo "Installed:"
echo "  git gh curl jq rg fd tmux btop"
echo "  net-tools openssh build-essential"
echo "  python3 uv nodejs npm kubectl"

echo
echo "========================================"
echo "NEXT STEPS (run on your LOCAL machine):"
echo "========================================"
echo
echo "# 1. Copy your SSH key to the VM:"
echo "scp ~/.ssh/id_ed25519.pub $USER_NAME@$VM_IP:/home/$USER_NAME/.ssh/authorized_keys"
echo
echo "# (or if you use RSA:)"
echo "scp ~/.ssh/id_rsa.pub $USER_NAME@$VM_IP:/home/$USER_NAME/.ssh/authorized_keys"
echo
echo "# 2. Copy your kubeconfig:"
echo "scp ~/.kube/config $USER_NAME@$VM_IP:/home/$USER_NAME/.kube/config"
echo
echo "# 3. SSH in:"
echo "ssh $USER_NAME@$VM_IP"
echo
echo "NOTE: You'll need to log in once with a password (or use the console)"
echo "to get shell access, then scp won't work until you have key auth."
echo "Alternative: paste the key via the VM console/hypervisor UI."
echo "========================================"
