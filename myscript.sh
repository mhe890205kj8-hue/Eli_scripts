#! /bin/bash
#script de prueba para kubernetes

POD_CIDR=$1
$SSH_key_path=$2
NODE_PORT=$3
SERVICE_TEMPLATE="nginx-service-demo.yaml.tpl"
SERVICE_FILE="nginx-service-demo.yaml"

#creacion del usuario admin_user y configuracion de ssh para que pueda acceder sin contraseña al nodo master y worker.
set -euo pipefail
 adduser --disabled-password --gecos "" admin_user
 usermod -aG sudo admin_user
 mkdir -p /home/admin_user/.ssh
 chmod 700 /home/admin_user/.ssh
 touch /home/admin_user/.ssh/authorized_keys
 install -m 600 -o admin_user -g admin_user $SSH_key_path /home/admin_user/.ssh/authorized_keys
 chmod 600 /home/admin_user/.ssh/authorized_keys
 chown -R admin_user:admin_user /home/admin_user/.ssh


#Instalacion de paquetes necesarios para kubernetes, configuracion de containerd y kubeadm, y despliegue de nginx como prueba de funcionamiento del cluster.
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
git clone https://github.com/mhe890205kj8-hue/Eli_scripts.git #revisar si esta bien en este punto del script
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
mkdir -p $HOME/.kube
 cp /etc/kubernetes/admin.conf $HOME/.kube/config
 chown $(id -u):$(id -g) $HOME/.kube/config
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/tigera-operator.yaml
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/custom-resources.yaml
sed -i "s#192.168.0.0/16#$POD_CIDR#g" custom-resources.yaml
kubectl create -f custom-resources.yaml
kubectl wait --for=condition=Ready node --all --timeout=600s
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
kubectl create deployment nginx-demo --image=nginx
#kubectl expose deployment nginx-demo --type=NodePort --port=80 --target-port=80 --name=nginx-service
if ! [[ "$NODE_PORT" =~ ^[0-9]+$ ]]; then
  echo "Error: NODE_PORT debe ser un número."
  exit 1
fi

if (( NODE_PORT < 30000 || NODE_PORT > 32767 )); then
  echo "Error: NODE_PORT debe estar entre 30000 y 32767."
  exit 1
fi

export NODE_PORT
envsubst < "$SERVICE_TEMPLATE" > "$SERVICE_FILE"

kubectl apply -f "$SERVICE_FILE"