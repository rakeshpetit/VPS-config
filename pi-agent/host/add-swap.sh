#!/bin/bash
# Optional: 2 GiB swapfile as an OOM safety net. Rollback:
#   swapoff /swapfile && rm /swapfile && sed -i '\|^/swapfile |d' /etc/fstab
set -euo pipefail
[ -e /swapfile ] && { echo "/swapfile already exists" >&2; exit 1; }
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
sysctl -w vm.swappiness=10
free -h
