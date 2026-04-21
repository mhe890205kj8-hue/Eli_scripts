apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-demo
  template:
    metadata:
      labels:
        app: nginx-demo
    spec:
      nodeName: k8scp
      containers:
      - name: nginx
        image: nginx:stable
        ports:
        - containerPort: 80
