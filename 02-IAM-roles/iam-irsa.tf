# IRSA: IAM Roles por tenant
variable "aws_region" {
  type = string
}

resource "aws_iam_role" "pod_irsa_tenant" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }
  
  name = "pod-irsa-${each.value.id}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:tenant-${each.value.id}:sa-${each.value.id}"
          }
        }
      }
    ]
  })
  
  tags = {
    Tenant = each.value.id
    Purpose = "pod-irsa"
  }
}

# Políticas IAM que los pods pueden asumir
resource "aws_iam_policy" "pod_permissions" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }
  
  name = "pod-policy-${each.value.id}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::${each.value.id}-data/*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${each.value.id}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage"
        ]
        Resource = "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:queue-${each.value.id}"
      }
    ]
  })
}

# Attach políticas a los roles IRSA
resource "aws_iam_role_policy_attachment" "irsa_attachments" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }
  
  role       = aws_iam_role.pod_irsa_tenant[each.key].name
  policy_arn = aws_iam_policy.pod_permissions[each.key].arn
}
