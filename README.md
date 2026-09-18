# vm-bootstrap

Bootstrap a fresh Debian 13 VM for AI agent work.

## Quick start (run from VM console)

If your fresh Debian VM has no `sudo` or `curl` installed, you can use `su` to switch to root, install curl, and run the script:

```bash
su -c 'apt-get update && apt-get install -y curl && curl -fsSL https://raw.githubusercontent.com/evertonramires/vm-bootstrap/main/install_vm_bootstrap.sh | bash'
```

If you already have `curl` and `sudo` configured for your user, run:

```bash
curl -fsSL https://raw.githubusercontent.com/evertonramires/vm-bootstrap/main/install_vm_bootstrap.sh | sudo bash
```

## What it does

- Updates and upgrades the system
- Installs: git, gh, curl, jq, ripgrep, fd, tmux, btop, net-tools, openssh, build-essential, python3, nodejs, npm
- Configures passwordless sudo for your user
- Installs uv (Python package manager)
- Installs kubectl (latest stable)
- Enables SSH server
- Prompts you to paste your SSH public key and kubeconfig
