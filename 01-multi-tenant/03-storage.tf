# S3 buckets por tenant
resource "aws_s3_bucket" "tenant_buckets" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }
  
  bucket = "${each.value.id}-data"
  
  tags = {
    Tenant      = each.value.id
    TenantName  = each.value.name
    Sensitive   = tostring(each.value.sensitive)
  }
}

resource "aws_s3_bucket_versioning" "sensitive_buckets" {
  for_each = {
    for t in var.tenants : 
    t.id => t if t.sensitive
  }
  
  bucket = aws_s3_bucket.tenant_buckets[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encrypt_buckets" {
  for_each = aws_s3_bucket.tenant_buckets
  
  bucket = each.value.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# KMS keys por tenant sensible
resource "aws_kms_key" "tenant_keys" {
  for_each = {
    for t in var.tenants : 
    t.id => t if t.sensitive
  }
  
  description = "KMS key para tenant ${each.value.name}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "kms:*"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            for role in aws_iam_role.tenant_role : 
            role.arn if role.value.tenant_id == each.key
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
}
