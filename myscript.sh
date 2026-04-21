#! /bin/bash
#script de prueba para kubernetes

#creacion del usuario admin_user y configuracion de ssh para que pueda acceder sin contraseña al nodo master y worker.
sudo adduser --disabled-password --gecos "" admin_user
sudo usermod -aG sudo admin_user
sudo mkdir -p /home/admin_user/.ssh
sudo chmod 700 /home/admin_user/.ssh
sudo touch /home/admin_user/.ssh/authorized_keys
    #Opción A: Copiar un archivo que ya existe con la llave publica
sudo install -m 600 -o admin_user -g admin_user /tmp/admin_user.pub /home/admin_user/.ssh/authorized_keys
    #Opción B: pasar la llave como una variable
#PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... comentario"
#echo "$PUBKEY" | sudo tee -a /home/admin_user/.ssh/authorized_keys >/dev/null
sudo chmod 600 /home/admin_user/.ssh/authorized_keys
sudo chown -R admin_user:admin_user /home/admin_user/.ssh


#Instalacion de containerd y configuracion del sistema para kubernetes.
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

sudo sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab #hay que revisar
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo systemctl is-active --quiet containerd || {
  echo "containerd no está activo"
  exit 1
}
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
sudo kubeadm init --pod-network-cidr=172.16.0.0/16
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/tigera-operator.yaml
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.31.4/manifests/custom-resources.yaml
#nano custom-resources.yaml  #Segun chatgpt calico hace los cambios por si mismo por lo cual este paso no es necesraio.
kubectl create -f custom-resources.yaml
kubectl taint nodes k8scp node-role.kubernetes.io/control-plane:NoSchedule-
kubectl create deployment nginx-demo --image=nginx
kubectl expose deployment nginx-demo --type=NodePort --port=80 --target-port=80 --name=nginx-service
