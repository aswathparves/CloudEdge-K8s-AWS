terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95.0"
    }
  }
}

provider "aws" {
  region     = "ap-south-1"
  access_key = "XXXXXXXXXXXXXXX" # Replace with your AWS access key
  secret_key = "XXXXXXXXXXXXXXXXXXXXXXXXXXXX" # Replace with your AWS secret key
}

#Create a VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

#Create a subnets
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = false
  tags = {
    Name                              = "private-subnet"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24" # Different CIDR from first private subnet
  availability_zone       = "ap-south-1b" # Different AZ
  map_public_ip_on_launch = false
  tags = {
    Name                              = "private-subnet-2"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

#Create an Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "internet-gateway"
  }
}

#Create an Nat Gateway
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "nat-gateway"
  }
}

#Create a route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id

  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "pub-lic" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "pri-vate" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

#Create a security group
resource "aws_security_group" "allow_ssh_http_https" {
  vpc_id      = aws_vpc.main.id
  name        = "allow_ssh_http_https"
  description = "Allow SSH, HTTP, and HTTPS inbound traffic"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a security group rule for ALB "Restrict ALB to CloudFront Only"
resource "aws_security_group_rule" "alb_cloudfront_only" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"] # Replace with CloudFront IPs: https://d7uri8nf7uskq.cloudfront.net/tools/list-cloudfront-ips
  security_group_id = module.eks.cluster_primary_security_group_id
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"  # This is the EKS module source from the Terraform Registry
  cluster_name    = "devops-challenge-cluster"
  cluster_version = "1.27"
  subnet_ids      = [aws_subnet.private.id, aws_subnet.private_2.id] # Must be PRIVATE subnets
  vpc_id          = aws_vpc.main.id

  eks_managed_node_groups = {
    default = {
      instance_type = "t3.micro"
      min_size      = 1
      max_size      = 2
      desired_size  = 2 # Explicitly set desired count

      # Add these critical parameters:
      subnet_ids = [aws_subnet.private.id, aws_subnet.private_2.id] # Must match cluster subnets
      iam_role_additional_policies = {
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AmazonEKS_CNI_Policy               = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
      }
    }
  }

  # Ensure the cluster can communicate with nodes
  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes to cluster API"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }
}

# Add this after your EKS module configuration
resource "aws_eks_access_entry" "admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::711387124378:root"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name   = module.eks.cluster_name
  principal_arn  = aws_eks_access_entry.admin.principal_arn
  policy_arn     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

#Create a Instance for Latency test
resource "aws_instance" "mumbai" {
  ami                         = "ami-0e35ddab05955cf57" # Ubuntu 20.04 LTS
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.allow_ssh_http_https.id]
  key_name                    = "asia1b"
  associate_public_ip_address = true
  availability_zone           = "ap-south-1a"
  user_data                   = <<-EOF
                                #!/bin/bash
                                apt-get update -y
                                apt-get install -y python3-pip curl
                                pip3 install requests boto3
                                mkdir -p /home/ubuntu/scripts
                                EOF

  tags = {
    Name = "latency-test-instance"
  }
}

#Create an S3 bucket for logs
resource "aws_s3_bucket" "logs" {
  bucket        = "devops-challenge-53241" # Must be globally unique
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#Create an Lambda function for Health check
resource "aws_lambda_function" "health_logger" {
  function_name = "health-logger"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "python3.8"
  filename      = "lambda.zip" # Created
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3_write" {
  name = "lambda-s3-write"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:PutObject"],
      Resource = "${aws_s3_bucket.logs.arn}/*"
    }]
  })
}

resource "aws_s3_bucket_policy" "allow_lambda" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = ["s3:PutObject"],
      Resource  = "${aws_s3_bucket.logs.arn}/*"
    }]
  })
}


#Create an Cloudfront distribution
resource "aws_cloudfront_distribution" "app" {
  origin {
    domain_name = "aec553d4776f4498d98fa8e6b49d78c8-419925269.ap-south-1.elb.amazonaws.com" # After EKS app deployment, get LB URL: `kubectl get svc -o wide`
    origin_id   = "eks-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"  # Use "https-only" if your ALB uses HTTPS
      origin_ssl_protocols   = ["TLSv1.2"] # Minimum TLS version
    }
  }
  enabled         = true
  is_ipv6_enabled = true
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "eks-origin"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}