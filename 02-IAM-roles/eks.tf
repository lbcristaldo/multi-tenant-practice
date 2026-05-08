# Cluster EKS
variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster and node group"
  type        = list(string)
}

resource "aws_eks_cluster" "main" {
  name     = "multitenant-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.28"

  vpc_config {
    subnet_ids = var.subnet_ids  # asumimos que ya existen
    endpoint_private_access = true
    endpoint_public_access  = false  # solo acceso interno
  }

  tags = {
    Name = "multitenant-eks"
  }
}

# Node group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "multitenant-nodes"
  node_role_arn   = aws_iam_role.eks_nodes_role.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = 3
    max_size     = 10
    min_size     = 2
  }

  instance_types = ["t3.medium"]
  
  tags = {
    Name = "multitenant-nodegroup"
  }
}

