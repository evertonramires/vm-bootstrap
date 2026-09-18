# vm-bootstrap

Bootstrap a fresh Debian 13 VM for AI agent work.

## Quick start (run as your normal user)

```bash
sudo bash -c 'apt-get update && apt-get install -y sudo curl passwd && /usr/sbin/usermod -aG sudo "$0" && export VM_USER="$0" && curl -fsSL https://raw.githubusercontent.com/evertonramires/vm-bootstrap/main/install_vm_bootstrap.sh | bash' -- "$(id -un)"
```

## Step by step

```bash
sudo apt-get update
sudo apt-get install -y sudo curl passwd
sudo /usr/sbin/usermod -aG sudo "$(id -un)"
VM_USER="$(id -un)" curl -fsSL https://raw.githubusercontent.com/evertonramires/vm-bootstrap/main/install_vm_bootstrap.sh | sudo bash
```

## What it does

- Updates and upgrades the system
- Installs: git, gh, curl, jq, ripgrep, fd, tmux, btop, net-tools, openssh, build-essential, python3, nodejs, npm
- Configures passwordless sudo for your user
- Installs uv (Python package manager)
- Installs kubectl (latest stable)
- Enables SSH server
- Prompts you to paste your SSH public key and kubeconfig
