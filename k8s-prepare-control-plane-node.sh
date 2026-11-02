#!/usr/bin/env bash

# Prepare a Debian 13 VM as a kubeadm node: kernel settings, containerd, kubeadm/kubelet/kubectl.
# Run as root (or via sudo). Override the version with: K8S_MINOR=v1.36 ./k8s-prep-node.sh

set -exuo pipefail

K8S_MINOR="${K8S_MINOR:-v1.35}"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (sudo $0)" >&2
    exit 1
fi

echo "==> Disabling swap"
swapoff -a
sed -i '/\sswap\s/ s/^/#/' /etc/fstab

echo "==> Kernel modules and sysctls"
cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# `net.bridge.bridge-nf-call-iptables`: pass all bridged ipv4/ipv6 traffic through the host's firewall (iptables)
# This applies host's firewall rules to traffic between containers.

# `net.ipv4.ip_forward`: allow this machine to act as a router.
# Why k8s needs it: a Linux machine drops a packet unless it's addressed to itself.
# But k8s node hosts many pods, each with its own unique IP address.
# This allows the host to route packet to pods inside it.

cat > /etc/sysctl.d/99-k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system > /dev/null

echo "==> Installing containerd"
apt update
apt install -y apt-transport-https ca-certificates curl gpg containerd

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable containerd
systemctl restart containerd

echo "==> Installing kubeadm, kubelet, kubectl (${K8S_MINOR})"
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
    | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
    > /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

echo "==> Sanity checks"
grep -c 'SystemdCgroup = true' /etc/containerd/config.toml
sysctl net.ipv4.ip_forward
kubeadm version -o short

echo "Done. Next: ./k8s-init-control-plane.sh"
