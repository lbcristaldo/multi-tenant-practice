resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "multitenant-vpc"
  }
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "tenants" {
  description = "List of tenant definitions for security groups"
  type = list(object({
    id   = string
    name = string
  }))
  default = []
}

variable "aws_region" {
  description = "The AWS region"
  type        = string
  default     = "us-east-1"
}

# Subnets públicas y privadas por AZ
resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "public-${var.availability_zones[count.index]}"
    Type = "public"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + length(var.availability_zones))
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "private-${var.availability_zones[count.index]}"
    Type = "private"
  }
}

# Internet Gateway (para salida a internet)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "multitenant-igw"
  }
}

# NAT Gateway (una por AZ para alta disponibilidad)
resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = {
    Name = "nat-eip-${count.index}"
  }
}

resource "aws_nat_gateway" "main" {
  count         = length(var.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "nat-${var.availability_zones[count.index]}"
  }
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "private-rt-${var.availability_zones[count.index]}"
  }
}

# Asociaciones de route tables
resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security Groups por tenant
resource "aws_security_group" "tenant" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  name        = "sg-${each.value.id}"
  description = "Security Group para tenant ${each.value.name}"
  vpc_id      = aws_vpc.main.id

  tags = {
    Tenant = each.value.id
    Name   = "tenant-sg-${each.value.id}"
  }
}

# Reglas de ingreso por tenant
resource "aws_vpc_security_group_ingress_rule" "tenant_http" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  security_group_id = aws_security_group.tenant[each.key].id

  cidr_ipv4   = aws_vpc.main.cidr_block
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80

  description = "HTTP desde dentro de la VPC"
}

resource "aws_vpc_security_group_ingress_rule" "tenant_https" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  security_group_id = aws_security_group.tenant[each.key].id

  cidr_ipv4   = aws_vpc.main.cidr_block
  from_port   = 443
  ip_protocol = "tcp"
  to_port     = 443

  description = "HTTPS desde dentro de la VPC"
}

resource "aws_vpc_security_group_ingress_rule" "tenant_app" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  security_group_id = aws_security_group.tenant[each.key].id

  cidr_ipv4   = aws_vpc.main.cidr_block
  from_port   = 3000  # puerto de la app
  ip_protocol = "tcp"
  to_port     = 3000

  description = "App port desde dentro de la VPC"
}

# Regla de salida
resource "aws_vpc_security_group_egress_rule" "tenant_egress" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  security_group_id = aws_security_group.tenant[each.key].id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"  # todo el tráfico

  description = "Egress permitido a cualquier destino"
}

# SG para RDS (acceso solo desde los SGs de tenant)
resource "aws_security_group" "rds" {
  name        = "sg-rds"
  description = "Security Group para RDS"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "rds-sg"
  }
}

# Regla de ingreso a RDS desde los SGs de tenant
resource "aws_vpc_security_group_ingress_rule" "rds_from_tenants" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  security_group_id = aws_security_group.rds.id

  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.tenant[each.key].id

  description = "PostgreSQL desde tenant ${each.value.id}"
}

# VPC Endpoints (conexión privada a servicios AWS)
# Endpoint para S3
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  tags = {
    Name = "s3-endpoint"
  }
}

# Endpoint para DynamoDB
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.dynamodb"

  tags = {
    Name = "dynamodb-endpoint"
  }
}

# Endpoint para ECR (para pulls de imágenes)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]

  tags = {
    Name = "ecr-api-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]

  tags = {
    Name = "ecr-dkr-endpoint"
  }
}

# Security Group para los endpoints de interfaz
resource "aws_security_group" "endpoints" {
  name        = "sg-endpoints"
  description = "Security Group para VPC endpoints"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "endpoints-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_tenants" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  security_group_id = aws_security_group.endpoints.id

  from_port                    = 443
  ip_protocol                  = "tcp"
  to_port                      = 443
  referenced_security_group_id = aws_security_group.tenant[each.key].id

  description = "HTTPS desde tenant ${each.value.id}"
}

resource "aws_vpc_security_group_egress_rule" "endpoints_egress" {
  security_group_id = aws_security_group.endpoints.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  description = "Egress permitido"
}
