# vm-bootstrap

```bash
USER_NAME="$(id -un)" && su -c "apt update && apt install -y sudo curl && /usr/sbin/usermod -aG sudo '$USER_NAME' && VM_USER='$USER_NAME' curl -fsSL https://raw.githubusercontent.com/evertonramires/vm-bootstrap/main/install_vm_bootstrap.sh | bash"
```
