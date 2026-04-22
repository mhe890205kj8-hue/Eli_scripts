#! /bin/bash
# Script de prueba para Kubernetes
# Descripción:
#   Configura un nodo master con kubeadm, instala containerd y Calico,
#   despliega un deployment nginx-demo y crea un servicio NodePort para acceso.
# Uso:
#   ./myscript.sh <POD_CIDR> <SSH_KEY_PATH> <NODE_PORT>
#     POD_CIDR      - rango de red de pods para el cluster (por ejemplo: 192.168.0.0/16)
#     SSH_KEY_PATH  - ruta al archivo de clave pública SSH para el usuario admin_user
#     NODE_PORT     - puerto NodePort para exponer el servicio nginx-demo
# Requisitos:
#   - ejecutar como root en una distribución Debian/Ubuntu compatible
#   - tener acceso a internet para descargar paquetes y manifiestos
#   - swap debe estar deshabilitado o será desactivado por el script
#
POD_CIDR=$1
SSH_key_path=$2
NODE_PORT=$3
SERVICE_TEMPLATE="nginx-service-demo.yml.tpl"
SERVICE_FILE="nginx-service-demo.yml"

# Asegura que el script falle inmediatamente en caso de error, uso de variable no inicializada o fallo en un pipe.
set -euo pipefail

# Crea el usuario local admin_user sin contraseña y configura SSH autorizada.
# Copia la clave pública especificada a /home/admin_user/.ssh/authorized_keys.
adduser --disabled-password --gecos "" admin_user
usermod -aG sudo admin_user
mkdir -p /home/admin_user/.ssh
chmod 700 /home/admin_user/.ssh
touch /home/admin_user/.ssh/authorized_keys
install -m 600 -o admin_user -g admin_user "$SSH_key_path" /home/admin_user/.ssh/authorized_keys
chmod 600 /home/admin_user/.ssh/authorized_keys
chown -R admin_user:admin_user /home/admin_user/.ssh


# Instala dependencias necesarias para Kubernetes y configura los repositorios oficiales.
# También prepara containerd como runtime de contenedores.
export DEBIAN_FRONTEND=noninteractive
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key |  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' |  tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y \
  kubelet kubeadm kubectl \
  apt-transport-https ca-certificates curl gpg \
  gettext-base \
  containerd \
  git
 apt-mark hold kubelet kubeadm kubectl
git clone https://github.com/mhe890205kj8-hue/Eli_scripts.git 
swapoff -a
sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab 
cat <<EOF |  tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
 modprobe overlay
 modprobe br_netfilter
cat <<EOF |  tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
 sysctl --system
 mkdir -p /etc/containerd
containerd config default |  tee /etc/containerd/config.toml >/dev/null
 sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
 systemctl restart containerd
 systemctl enable containerd
 systemctl is-active --quiet containerd || {
  echo "containerd no está activo"
  exit 1
}
 
 systemctl enable --now kubelet
 kubeadm init --pod-network-cidr="$POD_CIDR"

# Exporta el kubeconfig de administrador para que kubectl use el cluster recién creado.
export KUBECONFIG=/etc/kubernetes/admin.conf

# Copia el fichero de configuración a los directorios .kube de admin_lab y admin_user.
# Nota: el usuario admin_lab debe existir si se quiere usar esta configuración.
install -d -m 700 -o admin_lab -g admin_lab /home/admin_lab/.kube
install -m 600 -o admin_lab -g admin_lab /etc/kubernetes/admin.conf /home/admin_lab/.kube/config
install -d -m 700 -o admin_user -g admin_user /home/admin_user/.kube
install -m 600 -o admin_user -g admin_user /etc/kubernetes/admin.conf /home/admin_user/.kube/config

# Instala Calico como plugin de red para el cluster.
# Reemplaza el CIDR de ejemplo en los recursos de Calico por el valor suministrado.
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/tigera-operator.yaml
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/custom-resources.yaml
sed -i "s#192.168.0.0/16#$POD_CIDR#g" custom-resources.yaml
kubectl create -f custom-resources.yaml
kubectl wait --for=condition=Ready node --all --timeout=600s
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

# Crea un deployment nginx-demo de prueba en el cluster.
kubectl create deployment nginx-demo --image=nginx
#kubectl expose deployment nginx-demo --type=NodePort --port=80 --target-port=80 --name=nginx-service

# Valida que el puerto NodePort sea un número válido dentro del rango permitido.
if ! [[ "$NODE_PORT" =~ ^[0-9]+$ ]]; then
  echo "Error: NODE_PORT debe ser un número."
  exit 1
fi

if (( NODE_PORT < 30000 || NODE_PORT > 32767 )); then
  echo "Error: NODE_PORT debe estar entre 30000 y 32767."
  exit 1
fi
export NODE_PORT
cd Eli_scripts/manifiestos
envsubst < "$SERVICE_TEMPLATE" > "$SERVICE_FILE"
kubectl apply -f "$SERVICE_FILE"