variable "aws_region" {
  default = "us-east-1"
}

variable "use_localstack" {
  default = true  
}

variable "tenants" {
  type = list(object({
    name      = string
    id        = string
    envs      = list(string)
    sensitive = bool
  }))
  default = [
    {
      name      = "a"
      id        = "tn-001"
      envs      = ["dev", "staging", "prod"]
      sensitive = true
    },
    {
      name      = "b"
      id        = "tn-002"
      envs      = ["dev", "prod"]
      sensitive = false
    }
  ]
}

variable "organizational_roles" {
  type = map(object({
    policies = list(string)
    max_session_duration_hours = number
  }))
  default = {
    "qa" = {
      policies = ["ReadOnlyLogs", "ExecuteTests", "ReadStagingOnly"]
      max_session_duration_hours = 4
    }
    "webdev" = {
      policies = ["S3StaticDeploy", "CloudFrontManage", "NoDBNoAI"]
      max_session_duration_hours = 8
    }
    "ai-engineer" = {
      policies = ["SageMakerFull", "ECRAccess", "S3TrainingData"]
      max_session_duration_hours = 12
    }
  }
}