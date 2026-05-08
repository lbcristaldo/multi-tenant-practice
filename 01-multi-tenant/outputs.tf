output "tenant_roles" {
  value = {
    for role in aws_iam_role.tenant_role : 
    role.key => {
      role_name = role.name
      role_arn  = role.arn
      tenant    = role.value.tenant_id
      env       = role.value.environment
      type      = role.value.role_name
    }
  }
  description = "Roles IAM generados por tenant, ambiente y perfil"
}

output "tenant_buckets" {
  value = {
    for bucket in aws_s3_bucket.tenant_buckets : 
    bucket.tags.Tenant => bucket.id
  }
  description = "Buckets S3 por tenant"
}

output "kms_keys" {
  value = {
    for key in aws_kms_key.tenant_keys : 
    key.tags.Tenant => key.arn
  }
  description = "KMS keys por tenant sensible"
}

data "aws_caller_identity" "current" {}
