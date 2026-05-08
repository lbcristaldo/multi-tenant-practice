# Políticas base por rol organizacional
resource "aws_iam_policy" "role_policies" {
  for_each = var.organizational_roles
  
  name        = "policy-${each.key}"
  description = "Políticas base para rol ${each.key}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for policy_name in each.value.policies : 
      jsondecode(data.local.policy_definitions[policy_name].content)
    ]
  })
}

# Datos locales con definiciones de políticas
data "local_file" "policy_definitions" {
  for_each = toset(flatten([for r in var.organizational_roles : r.policies]))
  filename = "policies/${each.value}.json"
}

# Roles por tenant + ambiente + perfil
resource "aws_iam_role" "tenant_role" {
  for_each = {
    # Combinación cartesiana: tenant × env × role
    for combo in flatten([
      for t in var.tenants : [
        for env in t.envs : [
          for role_name, role_cfg in var.organizational_roles : {
            key            = "${t.id}-${env}-${role_name}"
            tenant_id      = t.id
            tenant_name    = t.name
            environment    = env
            role_name      = role_name
            max_duration   = role_cfg.max_session_duration_hours
            sensitive      = t.sensitive
          }
        ]
      ]
    ]) : combo.key => combo
  }
  
  name = "role-${each.value.tenant_id}-${each.value.environment}-${each.value.role_name}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:PrincipalTag/tenant" = each.value.tenant_id
            "aws:PrincipalTag/environment" = each.value.environment
          }
        }
      }
    ]
  })
  
  max_session_duration = each.value.max_duration * 3600
  
  tags = {
    Tenant      = each.value.tenant_id
    TenantName  = each.value.tenant_name
    Environment = each.value.environment
    Role        = each.value.role_name
    ManagedBy   = "terraform"
  }
}

# Attach policies base por rol
resource "aws_iam_role_policy_attachment" "base_policies" {
  for_each = {
    for r in aws_iam_role.tenant_role : 
    "${r.key}-base" => {
      role_name = r.name
      policy_arn = aws_iam_policy.role_policies[r.value.role_name].arn
    }
  }
  
  role       = each.value.role_name
  policy_arn = each.value.policy_arn
}

# Políticas específicas por tenant (ejemplo: acceso a su bucket)
resource "aws_iam_policy" "tenant_specific" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }
  
  name        = "policy-${each.value.id}-s3-access"
  description = "Acceso a recursos específicos del tenant ${each.value.name}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${each.value.id}-data/*",
          "arn:aws:s3:::${each.value.id}-data"
        ]
        Condition = {
          StringEquals = {
            "s3:prefix" = ["${each.value.id}/"]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${each.value.id}-*"
      }
    ]
  })
}

# Attach políticas específicas del tenant a los roles correspondientes
resource "aws_iam_role_policy_attachment" "tenant_specific" {
  for_each = {
    for role in aws_iam_role.tenant_role : 
    "${role.key}-tenant-specific" => {
      role_name   = role.name
      policy_arn  = aws_iam_policy.tenant_specific[role.value.tenant_id].arn
      tenant_id   = role.value.tenant_id
      environment = role.value.environment
    }
  }
  
  role       = each.value.role_name
  policy_arn = each.value.policy_arn
}