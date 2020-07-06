# Sample Demo Webapp with a MySql backend on EKS
The application runs on 3 docker containers running in different pods . 
The pods runs on worker nodes in a private subnet for security .
The backend MySQl runs in a container on 4 different pods for high availability .
The frontend web services run in different containers on 2 different multi container pods .
Backend MySql is exposed as a service to allow others pods to communicate to it
Front end discovers the backend service using the hostname "mysql"
Frontend service is exposed as LoadBalancer for hitting the services at port 5001 and 5000


Prerequisites to build the infrastructure required for the web application
- Terraform v0.12.28 
- EKS
- ECR for docker images

```
$ terraform -version
$ Terraform v0.12.28
```
### Run terraform to create the EKS cluster and ECR repositories
```
terraform init
terraform plan -out=makeitso.plan
terraform apply "makeitso.plan"
```
### Update Kube Config
```
$ aws eks update-kubeconfig --name eks-cluster --region us-east-2
$ kubectl get nodes
```
### Build Application Dockerfiles and push to ECR
```
$ aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin 875206965122.dkr.ecr.us-east-2.amazonaws.com
$ cd app
$ docker build -t eks-demo/app .
$ docker tag eks-demo/app:latest 875206965122.dkr.ecr.us-east-2.amazonaws.com/eks-demo/app:latest
$ docker push 875206965122.dkr.ecr.us-east-2.amazonaws.com/eks-demo/app:latest

$ cd ../app2
$ docker build -t eks-demo/app2 .
$ docker tag eks-demo/app2:latest 875206965122.dkr.ecr.us-east-2.amazonaws.com/eks-demo/app2:latest
$ docker push 875206965122.dkr.ecr.us-east-2.amazonaws.com/eks-demo/app2:latest

$ cd ../db
$ docker build -t eks-demo/db .
$ docker tag eks-demo/db:latest 875206965122.dkr.ecr.us-east-2.amazonaws.com/eks-demo/db:latest
$ docker push 875206965122.dkr.ecr.us-east-2.amazonaws.com/eks-demo/db:latest
```

### Deploy Pods on the Kubernetes
```
$ kubectl apply -f backend-deployment.yaml
$ kubectl apply -f backend-service.yaml
$ kubectl apply -f frontend-deployment.yaml
```
### Expose the webapp as a service via the LoadBalancer 
```
$ kubectl expose deployment webapp --type=LoadBalancer
```
### Get the hostname of the Load Balancer from the Load Balancer Ingress 
```
$ kubectl describe service/webapp
```
### Hit the service using curl or from browser
```
$ curl http://ab5af8c5544b9423c9a6658c49d31f41-1126381802.us-east-2.elb.amazonaws.com:5000/app/A
$ curl http://ab5af8c5544b9423c9a6658c49d31f41-1126381802.us-east-2.elb.amazonaws.com:5001/app/B
```

### Destroy Everything 
```
$ terraform destroy
```