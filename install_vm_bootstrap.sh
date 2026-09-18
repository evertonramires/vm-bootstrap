#!/bin/bash
set -e

USER_NAME="${SUDO_USER:-$(whoami)}"

sudo apt update
sudo apt upgrade -y
sudo /usr/sbin/usermod -aG sudo "$USER_NAME"

sudo tee "/etc/sudoers.d/$USER_NAME" >/dev/null <<EOF
$USER_NAME ALL=(ALL:ALL) NOPASSWD:ALL
EOF
sudo chmod 440 "/etc/sudoers.d/$USER_NAME"

sudo apt install -y \
  git gh curl jq ripgrep fd-find tmux btop net-tools \
  openssh-client openssh-server sudo build-essential \
  python3 nodejs npm

# uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

sudo systemctl enable --now ssh

# SSH public key (optional)
echo
echo "Paste your SSH public key (or press Enter to skip):"
read -r SSH_KEY

if [ -n "$SSH_KEY" ]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    echo "$SSH_KEY" >> "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    echo "SSH key installed."
else
    echo "SSH key skipped."
fi

# Kubeconfig (optional)
echo
echo "Paste your kubeconfig (or press Enter to skip):"
read -r KUBECONFIG_CONTENT

if [ -n "$KUBECONFIG_CONTENT" ]; then
    mkdir -p "$HOME/.kube"
    chmod 700 "$HOME/.kube"
    printf '%s\n' "$KUBECONFIG_CONTENT" > "$HOME/.kube/config"
    chmod 600 "$HOME/.kube/config"
    echo "Kubeconfig installed."
else
    echo "Kubeconfig skipped."
fi

echo
echo "========================================"
echo "VM READY"
echo "========================================"
echo
echo "SSH as: $USER_NAME"
echo
echo "IP addresses:"
ip -4 addr show | awk '/inet / {print "  " $2 "  (" $NF ")"}'
echo
echo "Example:"
echo "  ssh $USER_NAME@<IP>"
echo
echo "Sudo: passwordless"
echo "========================================"