variable "tenants" {
  type = list(object({
    id = string
  }))
}

# SQS por tenant (cola para procesamiento)
resource "aws_sqs_queue" "tenant_queues" {
  for_each = {
    for t in var.tenants :
    t.id => t
  }
  
  name = "queue-${each.value.id}"
  
  tags = {
    Tenant = each.value.id
  }
}