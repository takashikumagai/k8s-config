#!/usr/bin/env bash

# Initialize a single-node kubeadm control plane, install Cilium as the CNI,
# and allow workloads to schedule on the control plane node.
# Run as root (or via sudo) after k8s-prepare-control-plane-node.sh.

set -exuo pipefail

# Make sure that this does not overlap the current LAN
POD_CIDR="${POD_CIDR:-10.223.0.0/16}"
export KUBECONFIG=/etc/kubernetes/admin.conf

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (sudo $0)" >&2
    exit 1
fi

echo "==> kubeadm init"
kubeadm init --pod-network-cidr="${POD_CIDR}"

echo "==> kubeconfig for ${SUDO_USER:-root}"
target_user="${SUDO_USER:-root}"
target_home="$(getent passwd "${target_user}" | cut -d: -f6)"
mkdir -p "${target_home}/.kube"
cp /etc/kubernetes/admin.conf "${target_home}/.kube/config"
chown -R "${target_user}:" "${target_home}/.kube"

echo "==> Installing Cilium CLI"
cli_version="$(curl -fsSL https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)"
base_url="https://github.com/cilium/cilium-cli/releases/download/${cli_version}"
tmp="$(mktemp -d)"
curl -fsSL --remote-name-all --output-dir "${tmp}" \
    "${base_url}/cilium-linux-amd64.tar.gz" "${base_url}/cilium-linux-amd64.tar.gz.sha256sum"
(cd "${tmp}" && sha256sum --check cilium-linux-amd64.tar.gz.sha256sum)
tar -xzf "${tmp}/cilium-linux-amd64.tar.gz" -C /usr/local/bin cilium
rm -rf "${tmp}"

echo "==> Installing Cilium CNI"
cilium install --set ipam.operator.clusterPoolIPv4PodCIDRList="${POD_CIDR}"
cilium status --wait

echo "==> Allowing workloads on the control plane node"
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

kubectl get nodes -o wide
kubectl get pods -A
