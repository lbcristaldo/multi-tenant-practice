variable "availability_zones" {
    type    = list(string)
    default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "db_password" {
    type      = string
    sensitive = true
}

# Networking outputs
output "vpc_id" {
    value = aws_vpc.main.id
}

output "tenant_security_groups" {
    value = {
        for sg in aws_security_group.tenant :
        sg.tags.Tenant => sg.id
    }
}

output "private_subnets" {
    value = aws_subnet.private[*].id
}

output "rds_endpoint" {
    value = aws_db_instance.postgres.endpoint
    sensitive = true
}

output "vpc_endpoints" {
    value = {
        s3       = aws_vpc_endpoint.s3.id
        dynamodb = aws_vpc_endpoint.dynamodb.id
        ecr_api  = aws_vpc_endpoint.ecr_api.id
        ecr_dkr  = aws_vpc_endpoint.ecr_dkr.id
    }
}