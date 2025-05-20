#!/bin/bash
# 1. Build and push Docker image
docker build -t flask-app .
docker tag flask-app:latest yourdockerhubusername/flask-app:latest
docker push yourdockerhubusername/flask-app:latest

# 2. Deploy to EKS
kubectl apply -f deployment.yaml
kubectl apply -f hpa.yaml
echo "HPA configured: min=1, max=3, CPU=50%"
kubectl apply -f service.yaml

# 3. Wait for ALB to be ready
echo "Waiting for ALB to be ready..."
sleep 120

# 4. Update CloudFront with ALB DNS
ALB_DNS=$(kubectl get svc flask-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
terraform apply -var="alb_dns_name=$ALB_DNS" -auto-approve

# 5. Verify
echo "CloudFront URL: $(terraform output cloudfront_url)"

# 6. Run latency test
ssh -i asia1b.pem ubuntu@<MUMBAI_EC2_IP> "python3 latency_test.py"