output "app_instance" {
  value = aws_instance.mumbai.public_ip
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint

}