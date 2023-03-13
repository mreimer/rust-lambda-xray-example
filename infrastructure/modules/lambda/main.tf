locals {
  resource_name        = "${var.prefix}-${var.name}"
  root_dir             = "${path.module}/../../../src"
  lambda_timeout       = 15
  lambda_memory_size   = 128
  build_args           = "--build-arg base_image=${var.base_image} --build-arg log_level=${var.log_level}"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_lambda_function" "lambda_function" {
  function_name = local.resource_name

  image_uri    = "${aws_ecr_repository.lambda_repository.repository_url}@${data.aws_ecr_image.lambda_image.id}"
  package_type = "Image"

  timeout     = local.lambda_timeout
  memory_size = local.lambda_memory_size
  role        = aws_iam_role.lambda_role.arn

  tracing_config {
    mode = "Active"
  }

  dynamic "environment" {
    for_each = var.env_vars != null ? [1] : []
    content {
      variables = var.env_vars
    }
  }
}

resource "aws_ecr_repository" "lambda_repository" {
  name = local.resource_name
  force_delete = true
}

resource "null_resource" "lambda_ecr_image_builder" {
  triggers = {
    docker_base       = filesha256("${local.root_dir}/Dockerfile.base")
    docker_file       = filesha256("${local.root_dir}/Dockerfile")
    collector_file    = filesha256("${local.root_dir}/otel-config.yaml")
    cargo_file        = filesha256("${local.root_dir}/Cargo.toml")
    cargo_lock_file   = filesha256("${local.root_dir}/Cargo.lock")
    handlers          = sha256(join("", [for f in fileset("${local.root_dir}/handlers", "**") : filesha256("${local.root_dir}/handlers/${f}")]))
  }

  provisioner "local-exec" {
    working_dir = local.root_dir
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com
      set -e
      docker image build -t ${aws_ecr_repository.lambda_repository.repository_url}:latest ${local.build_args} .
      docker push ${aws_ecr_repository.lambda_repository.repository_url}:latest
    EOT
  }
}

data "aws_ecr_image" "lambda_image" {
  depends_on = [
    null_resource.lambda_ecr_image_builder
  ]

  repository_name = local.resource_name
  image_tag       = "latest"
}

resource "aws_ecr_lifecycle_policy" "lambda_lifecycle" {
  repository = aws_ecr_repository.lambda_repository.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last image only",
            "selection": {
                "tagStatus": "any",
                "countType": "imageCountMoreThan",
                "countNumber": 1
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.prefix}/${var.name}"
  retention_in_days = var.log_retention_in_days
}

resource "aws_iam_role" "lambda_role" {
  name = "${local.resource_name}-iam-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = ""
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "basic_lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "xray_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXrayFullAccess"
}
