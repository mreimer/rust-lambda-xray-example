resource "aws_ecr_repository" "base" {
  name = local.prefix
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "base_lifecycle" {
  repository = aws_ecr_repository.base.name
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

resource "null_resource" "base_image_builder" {
  triggers = {
    docker_base     = filesha256("${local.root_dir}/src/Dockerfile.base")
    cargo_file      = filesha256("${local.root_dir}/src/Cargo.toml")
    cargo_lock_file = filesha256("${local.root_dir}/src/Cargo.lock")
    handlers        = sha256(join("", [for f in fileset("${local.root_dir}/src/handlers", "**") : filesha256("${local.root_dir}/src/handlers/${f}")]))
  }

  provisioner "local-exec" {
    working_dir = "${local.root_dir}/src"
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com
      set -e
      docker image build -f Dockerfile.base -t ${aws_ecr_repository.base.repository_url}:latest .
      docker push ${aws_ecr_repository.base.repository_url}:latest
    EOT
  }
}
