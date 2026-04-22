apiVersion: v1
kind: Service
metadata:
  labels:
    app: nginx-demo
  name: nginx-service
  namespace: default
spec:
  type: NodePort
  selector:
    app: nginx-demo
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
      nodePort: ${NODE_PORT}

