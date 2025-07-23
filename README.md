# AWS DevOps Challenge: Flask on EKS with CloudFront

[![Terraform](https://img.shields.io/badge/Terraform-v1.5+-blue)](https://terraform.io)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-v1.27-green)](https://kubernetes.io)
[![AWS](https://img.shields.io/badge/AWS-CloudFront-orange)](https://aws.amazon.com/cloudfront/)

## 📌 Overview
Deployment of a highly available Flask application on AWS with:
- **EKS** for orchestration
- **CloudFront** for global edge caching
- **Auto-scaling** (HPA) based on CPU
- **Serverless** health monitoring (Lambda + S3)



## 🏗️ Architecture

```mermaid
graph LR
    A[User] --> B[CloudFront CDN]
    A --> C[ALB]
    B --> D[EKS Cluster]
    C --> D
    D --> E[Flask Pods]
    E --> F[(ECR)]
    C --> G[Lambda]
    G --> H[(S3 Bucket)]
    D --> I[Auto-Scaling Group]
