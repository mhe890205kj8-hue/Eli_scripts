#! /bin/bash
# Script de prueba para Kubernetes
# Descripción:
#   Configura un nodo control-plane con kubeadm, instala containerd, Calico y Helm.
#   Deja el nodo listo para probar charts de Helm manualmente después.
#
# Uso:
#   ./myscript.sh <POD_CIDR> <SSH_KEY_PATH>
#
#     POD_CIDR      - rango de red de pods para el cluster, por ejemplo: 192.168.0.0/16
#     SSH_KEY_PATH  - ruta al archivo de clave pública SSH para el usuario admin_user
#
# Requisitos:
#   - ejecutar como root en una distribución Debian/Ubuntu compatible
#   - tener acceso a internet para descargar paquetes y manifiestos
#   - swap debe estar deshabilitado o será desactivado por el script

set -euo pipefail

POD_CIDR=$1
SSH_key_path=$2

# Crea el usuario local admin_user sin contraseña y configura SSH autorizada.
adduser --disabled-password --gecos "" admin_user
usermod -aG sudo admin_user
mkdir -p /home/admin_user/.ssh
chmod 700 /home/admin_user/.ssh
touch /home/admin_user/.ssh/authorized_keys
install -m 600 -o admin_user -g admin_user "$SSH_key_path" /home/admin_user/.ssh/authorized_keys
chmod 600 /home/admin_user/.ssh/authorized_keys
chown -R admin_user:admin_user /home/admin_user/.ssh

# Instala dependencias necesarias para Kubernetes y configura los repositorios oficiales.
export DEBIAN_FRONTEND=noninteractive

mkdir -p -m 755 /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update

apt-get install -y \
  kubelet kubeadm kubectl \
  apt-transport-https ca-certificates curl gpg \
  containerd \
  git

# Instala Helm para que después puedas probar charts manualmente.
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

apt-mark hold kubelet kubeadm kubectl

# Desactiva swap.
swapoff -a
sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab

# Configura módulos requeridos por Kubernetes.
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Configura parámetros de red requeridos por Kubernetes.
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system

# Configura containerd.
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml >/dev/null

sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

systemctl is-active --quiet containerd || {
  echo "containerd no está activo"
  exit 1
}

systemctl enable --now kubelet

# Inicializa el cluster.
kubeadm init --pod-network-cidr="$POD_CIDR"

# Exporta el kubeconfig de administrador para que kubectl use el cluster recién creado.
export KUBECONFIG=/etc/kubernetes/admin.conf

# Copia el kubeconfig para admin_lab si el usuario existe.
if id "admin_lab" &>/dev/null; then
  install -d -m 700 -o admin_lab -g admin_lab /home/admin_lab/.kube
  install -m 600 -o admin_lab -g admin_lab /etc/kubernetes/admin.conf /home/admin_lab/.kube/config
else
  echo "Usuario admin_lab no existe, se omite configuración de kubeconfig para admin_lab."
fi

# Copia el kubeconfig para admin_user.
install -d -m 700 -o admin_user -g admin_user /home/admin_user/.kube
install -m 600 -o admin_user -g admin_user /etc/kubernetes/admin.conf /home/admin_user/.kube/config

# Instala Calico como plugin de red para el cluster.
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/tigera-operator.yaml

curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/custom-resources.yaml
sed -i "s#192.168.0.0/16#$POD_CIDR#g" custom-resources.yaml

kubectl create -f custom-resources.yaml

# Espera a que el nodo esté listo.
kubectl wait --for=condition=Ready node --all --timeout=600s

# Permite programar pods en el nodo control-plane para laboratorio de un solo nodo.
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

echo "Nodo Kubernetes listo."
echo "Helm instalado correctamente."
