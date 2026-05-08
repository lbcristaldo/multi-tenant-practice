variable "tenants" {
  type = list(object({
    id = string
    name = string
  }))
  description = "List of tenants"
}
variable "environment" {
  type        = string
  description = "Environment (dev, staging, prod)"
  default     = "dev"  
}
variable "aws_region" {
  type        = string
  description = "La región de AWS donde se desplegarán los recursos de CloudWatch (recomiendo A-Z)"
  default     = "us-east-1" 
}
variable "slack_webhook_url" {
  type        = string
  description = "URL del webhook de Slack para recibir alertas (opcional)"
  default     = ""  
}
variable "alert_email" {
  type        = string
  description = "El mail donde se reciben las alertas (SNS)"
  default     = "alert@taxidancers.com"
}
# 1. GRUPOS DE LOGS

resource "aws_cloudwatch_log_group" "application" {
  name              = "/taxidancers/application"
  retention_in_days = 30
  
  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_cloudwatch_log_group" "access" {
  name              = "/taxidancers/access"
  retention_in_days = 7
  
  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_cloudwatch_log_group" "error" {
  name              = "/taxidancers/errors"
  retention_in_days = 90
  
  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Container Insights para EKS
resource "aws_cloudwatch_log_group" "container_insights" {
  name              = "/aws/containerinsights/${aws_eks_cluster.main.name}/performance"
  retention_in_days = 30
}

# 2. DASHBOARDS POR TENANT

resource "aws_cloudwatch_dashboard" "tenant" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  dashboard_name = "Tenant-${each.value.name}-Dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      # Widget 1: Imágenes procesadas vs fallidas
      {
        type = "metric"
        properties = {
          metrics = [
            ["TaxiDancers", "ImagesProcessed", "Tenant", each.value.id, { "stat": "Sum", "label": "Exitosas" }],
            [".", "ImagesFailed", ".", ".", { "stat": "Sum", "label": "Fallidas" }]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Imágenes procesadas - ${each.value.name}"
          stacked = false
          view = "timeSeries"
        }
      },
      # Widget 2: Latencia p99
      {
        type = "metric"
        properties = {
          metrics = [
            ["TaxiDancers", "ProcessingLatency", "Tenant", each.value.id, { "stat": "p99", "label": "P99" }],
            [".", ".", ".", ".", { "stat": "p95", "label": "P95" }],
            [".", ".", ".", ".", { "stat": "p50", "label": "P50" }]
          ]
          period = 60
          stat   = "p99"
          region = var.aws_region
          title  = "Latencia (ms) - ${each.value.name}"
          unit   = "Milliseconds"
        }
      },
      # Widget 3: Error rate
      {
        type = "metric"
        properties = {
          metrics = [
            ["TaxiDancers", "ErrorRate", "Tenant", each.value.id, { "stat": "Average", "label": "Error %" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Error rate - ${each.value.name}"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      # Widget 4: Queue depth (SQS)
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "queue-${each.value.id}", { "stat": "Average", "label": "Mensajes encolados" }],
            [".", "ApproximateNumberOfMessagesNotVisible", ".", ".", { "stat": "Average", "label": "En procesamiento" }]
          ]
          period = 60
          stat   = "Average"
          region = var.aws_region
          title  = "Queue depth - ${each.value.name}"
        }
      },
      # Widget 5: CPU/Memoria (Container Insights)
      {
        type = "metric"
        properties = {
          metrics = [
            ["ContainerInsights", "pod_cpu_utilization", "Namespace", "tenant-${each.value.id}", { "stat": "Average", "label": "CPU %" }],
            [".", "pod_memory_utilization", ".", ".", { "stat": "Average", "label": "Memory %" }]
          ]
          period = 60
          stat   = "Average"
          region = var.aws_region
          title  = "🖥️ Recursos - ${each.value.name}"
        }
      },
      # Widget 6: Logs recientes
      {
        type = "log"
        properties = {
          query = "SOURCE '/taxidancers/application' | fields @timestamp, @message | filter tenant = '${each.value.id}' and level = 'ERROR' | sort @timestamp desc | limit 20"
          region = var.aws_region
          title = "Últimos errores - ${each.value.name}"
          view = "table"
        }
      }
    ]
  })
}

# Dashboard global (todos los tenants)
resource "aws_cloudwatch_dashboard" "global" {
  dashboard_name = "Global-Multitenant-Overview"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            for t in var.tenants : 
            ["TaxiDancers", "ImagesProcessed", "Tenant", t.id, { "label": t.name, "stat": "Sum" }]
          ]
          period = 3600
          stat   = "Sum"
          region = var.aws_region
          title  = "Imágenes procesadas (última hora)"
          stacked = true
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            for t in var.tenants : 
            ["TaxiDancers", "ErrorRate", "Tenant", t.id, { "label": t.name, "stat": "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Error rate por tenant"
          yAxis = {
            left = {
              min = 0
              max = 10
            }
          }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            for t in var.tenants : 
            ["TaxiDancers", "ProcessingLatency", "Tenant", t.id, { "label": t.name, "stat": "p99" }]
          ]
          period = 300
          stat   = "p99"
          region = var.aws_region
          title  = "Latencia p99 por tenant"
          unit   = "Milliseconds"
        }
      }
    ]
  })
}

# 3. ALARMAS POR TENANT

# SNS Topic para alertas
resource "aws_sns_topic" "alerts" {
  name = "taxidancers-alerts"
  
  tags = {
    Environment = var.environment
  }
}

# Suscripciones
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "slack" {
  count = var.slack_webhook_url != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
}

# Alarma 1: Error rate > 1%
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  alarm_name          = "tenant-${each.value.id}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ErrorRate"
  namespace           = "TaxiDancers"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Error rate > 1% para tenant ${each.value.name} durante 15 minutos"
  
  dimensions = {
    Tenant = each.value.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  
  tags = {
    Tenant = each.value.id
  }
}

# Alarma 2: Latencia > 30 segundos
resource "aws_cloudwatch_metric_alarm" "high_latency" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  alarm_name          = "tenant-${each.value.id}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ProcessingLatency"
  namespace           = "TaxiDancers"
  period              = 300
  statistic           = "p99"
  threshold           = 30000  # 30 segundos
  alarm_description   = "Latencia p99 > 30s para tenant ${each.value.name}"
  
  dimensions = {
    Tenant = each.value.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  
  tags = {
    Tenant = each.value.id
  }
}

# Alarma 3: Queue depth > 500 mensajes
resource "aws_cloudwatch_metric_alarm" "queue_depth" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  alarm_name          = "tenant-${each.value.id}-queue-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 500
  alarm_description   = "Queue depth > 500 mensajes para tenant ${each.value.name}"
  
  dimensions = {
    QueueName = "queue-${each.value.id}"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  
  tags = {
    Tenant = each.value.id
  }
}

# Alarma 4: Tenant inactivo (0 imágenes en 2 horas)
resource "aws_cloudwatch_metric_alarm" "no_images" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  alarm_name          = "tenant-${each.value.id}-no-images"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 24  # 24 periodos de 5 minutos = 2 horas
  metric_name         = "ImagesProcessed"
  namespace           = "TaxiDancers"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Tenant ${each.value.name} no procesó imágenes en las últimas 2 horas"
  
  dimensions = {
    Tenant = each.value.id
  }
  
  treat_missing_data = "breaching"
  alarm_actions = [aws_sns_topic.alerts.arn]
  
  tags = {
    Tenant = each.value.id
  }
}

# Alarma 5: CPU alto en namespace del tenant
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  alarm_name          = "tenant-${each.value.id}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "pod_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80  # 80% de CPU
  alarm_description   = "CPU > 80% en namespace tenant-${each.value.id}"
  
  dimensions = {
    Namespace = "tenant-${each.value.id}"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  
  tags = {
    Tenant = each.value.id
  }
}

resource "aws_xray_group" "tenant" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  group_name        = "tenant-${each.value.id}"
  filter_expression = "service(\"taxidancers-${each.value.id}\")"
  
  tags = {
    Tenant = each.value.id
  }
}

# 4. X-RAY (Tracing distribuido)

resource "aws_xray_sampling_rule" "tenant" {
    for_each = {
      for t in var.tenants : 
      t.id => t
  }

  rule_name      = "tenant-${each.value.id}-sampling"
  priority       = 10
  version        = 1
  reservoir_size = 5
  fixed_rate     = 0.05
  
  resource_arn   = aws_xray_group.tenant[each.key].arn
  
  host           = "*"
  http_method    = "*"
  service_name   = "taxidancers-${each.value.id}"
  service_type   = "*"
  url_path       = "*"
  
  attributes = {
    Tenant = each.value.id
  }
}

# 5. OUTPUTS

output "cloudwatch_dashboard_urls" {
  value = {
    for dashboard in aws_cloudwatch_dashboard.tenant :
    dashboard.dashboard_name => "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${dashboard.dashboard_name}"
  }
  description = "URLs de los dashboards de CloudWatch por tenant"
}

output "global_dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=Global-Multitenant-Overview"
  description = "URL del dashboard global"
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
  description = "ARN del topic SNS para alertas"
}

output "cloudwatch_log_groups" {
  value = {
    application = aws_cloudwatch_log_group.application.name
    access      = aws_cloudwatch_log_group.access.name
    errors      = aws_cloudwatch_log_group.error.name
    insights    = aws_cloudwatch_log_group.container_insights.name
  }
}
