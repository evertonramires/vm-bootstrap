#!/bin/bash
set -Eeuo pipefail

# ------------------------------------------------------------
# VM BOOTSTRAP FOR AI AGENT VMS
# Debian 13
# ------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------
# Determine target user
# ------------------------------------------------------------

if [ -n "${VM_USER:-}" ]; then
    USER_NAME="$VM_USER"
elif [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    USER_NAME="$SUDO_USER"
elif [ "$(id -u)" -ne 0 ]; then
    USER_NAME="$(id -un)"
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

# ------------------------------------------------------------
# Privilege handling
# ------------------------------------------------------------

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if ! command -v sudo >/dev/null 2>&1; then
        echo "ERROR: sudo is not installed."
        echo "Run the bootstrap as root."
        exit 1
    fi
    SUDO="sudo"
fi

run_as_user() {
    if [ "$(id -u)" -eq 0 ]; then
        runuser -u "$USER_NAME" -- "$@"
    else
        sudo -u "$USER_NAME" -H "$@"
    fi
}

# ------------------------------------------------------------
# Base system
# ------------------------------------------------------------

echo
echo "==> Updating Debian"
$SUDO apt-get update
$SUDO apt-get upgrade -y

echo
echo "==> Installing packages"
$SUDO apt-get install -y \
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
    build-essential \
    python3 \
    nodejs \
    npm

# Debian calls the binary fdfind.
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    $SUDO ln -s /usr/bin/fdfind /usr/local/bin/fd
fi

# ------------------------------------------------------------
# Passwordless sudo
# ------------------------------------------------------------

echo
echo "==> Configuring passwordless sudo"

$SUDO /usr/sbin/usermod -aG sudo "$USER_NAME"

SUDOERS_FILE="/etc/sudoers.d/$USER_NAME"

printf '%s\n' \
    "$USER_NAME ALL=(ALL:ALL) NOPASSWD:ALL" |
    $SUDO tee "$SUDOERS_FILE" >/dev/null

$SUDO chmod 440 "$SUDOERS_FILE"
$SUDO visudo -cf "$SUDOERS_FILE"

# ------------------------------------------------------------
# uv
# ------------------------------------------------------------

echo
echo "==> Installing uv"

TMP_UV="$(mktemp)"

curl -fsSL https://astral.sh/uv/install.sh -o "$TMP_UV"

$SUDO install -m 0755 -o "$USER_NAME" -g "$USER_GROUP" \
    "$TMP_UV" "$TMP_UV"

run_as_user env \
    HOME="$USER_HOME" \
    UV_INSTALL_DIR="$USER_HOME/.local/bin" \
    sh "$TMP_UV"

rm -f "$TMP_UV"

# Ensure .local/bin is in bash PATH.
BASHRC="$USER_HOME/.bashrc"

if ! grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "$BASHRC" 2>/dev/null; then
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' |
        $SUDO tee -a "$BASHRC" >/dev/null
fi

$SUDO chown "$USER_NAME:$USER_GROUP" "$BASHRC"

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

$SUDO install -o root -g root -m 0755 \
    "$TMP_KUBECTL/kubectl" /usr/local/bin/kubectl

rm -rf "$TMP_KUBECTL"

# ------------------------------------------------------------
# SSH
# ------------------------------------------------------------

echo
echo "==> Enabling SSH"

$SUDO systemctl enable --now ssh

# ------------------------------------------------------------
# Interactive input
# IMPORTANT: use /dev/tty because this script may run via
# curl | bash.
# ------------------------------------------------------------

if [ -r /dev/tty ]; then
    INPUT="/dev/tty"
else
    INPUT="/dev/stdin"
fi

# ------------------------------------------------------------
# SSH public key
# ------------------------------------------------------------

echo
echo "Paste your SSH public key."
echo "Press Enter with an empty line to skip."

IFS= read -r SSH_KEY < "$INPUT" || SSH_KEY=""

if [ -n "$SSH_KEY" ]; then
    $SUDO install -d -m 700 \
        -o "$USER_NAME" -g "$USER_GROUP" \
        "$USER_HOME/.ssh"

    AUTH_KEYS="$USER_HOME/.ssh/authorized_keys"

    if [ ! -f "$AUTH_KEYS" ] ||
       ! $SUDO grep -qxF "$SSH_KEY" "$AUTH_KEYS"; then
        printf '%s\n' "$SSH_KEY" |
            $SUDO tee -a "$AUTH_KEYS" >/dev/null
    fi

    $SUDO chown "$USER_NAME:$USER_GROUP" "$AUTH_KEYS"
    $SUDO chmod 600 "$AUTH_KEYS"

    echo "SSH key installed."
else
    echo "SSH key skipped."
fi

# ------------------------------------------------------------
# Kubeconfig
# ------------------------------------------------------------

echo
echo "Paste kubeconfig."
echo "Press Enter immediately to skip."
echo "Otherwise finish by typing KUBECONFIG_DONE on its own line."

IFS= read -r FIRST_LINE < "$INPUT" || FIRST_LINE=""

if [ -n "$FIRST_LINE" ]; then
    $SUDO install -d -m 700 \
        -o "$USER_NAME" -g "$USER_GROUP" \
        "$USER_HOME/.kube"

    KUBE_TMP="$(mktemp)"

    printf '%s\n' "$FIRST_LINE" > "$KUBE_TMP"

    while IFS= read -r LINE < "$INPUT"; do
        [ "$LINE" = "KUBECONFIG_DONE" ] && break
        printf '%s\n' "$LINE" >> "$KUBE_TMP"
    done

    $SUDO install -m 600 \
        -o "$USER_NAME" -g "$USER_GROUP" \
        "$KUBE_TMP" "$USER_HOME/.kube/config"

    rm -f "$KUBE_TMP"

    echo "Kubeconfig installed."
else
    echo "Kubeconfig skipped."
fi

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
echo "SSH:"
echo "  ssh $USER_NAME@<IP>"

echo
echo "Installed:"
echo "  git gh curl jq rg fd tmux btop"
echo "  net-tools openssh build-essential"
echo "  python3 uv nodejs npm kubectl"

echo
echo "IMPORTANT:"
echo "Log out/in once so the sudo group is reflected in normal sessions."
echo "========================================"