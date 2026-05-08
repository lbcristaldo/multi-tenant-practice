output "irsa_roles" {
  value = {
    for role in aws_iam_role.pod_irsa_tenant :
    role.tags.Tenant => role.arn
  }
  description = "IRSA roles por tenant"
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
  description = "Endpoint del cluster EKS"
}

output "kubectl_command" {
  value = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name}"
  description = "Comando para configurar kubectl"
}
