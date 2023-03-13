locals {
  root_dir   = "${path.module}/.."
  prefix     = "lambda-xray"
}

module "lambda" {
  depends_on = [null_resource.base_image_builder]
  source = "./modules/lambda"

  name = "example"
  base_image = "${aws_ecr_repository.base.repository_url}:latest"
  prefix = local.prefix
}
