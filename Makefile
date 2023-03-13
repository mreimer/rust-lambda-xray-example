SHELL := /bin/bash

TF_VAR_service_name := lambda-xray
export TF_VAR_service_name
BUCKET = "mreimer-infra"

terraform_init = terraform -chdir=infrastructure init -reconfigure -backend-config="key=${TF_VAR_service_name}" -backend-config="bucket=${BUCKET}"
terraform_apply = terraform -chdir=infrastructure apply -auto-approve
terraform_output = terraform -chdir=infrastructure output -raw $(1)
terraform = terraform -chdir=infrastructure $(1)

check_defined = \
	$(strip $(foreach 1,$1, \
		$(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = \
	$(if $(value $1),, \
		$(error Undefined $1$(if $2, ($2))))

init:
	@echo "Initializing with the following configuration:"
	@echo "Backend bucket: ${BUCKET}"
	@echo "Service name: ${TF_VAR_service_name}"
	@$(call terraform_init)
	@echo "Terraform initialized"

plan: init
	@$(call terraform, "plan")

teardown: init
	@echo "Destroying ${TF_VAR_service_name}, branch ${TF_VAR_branch}"
	@$(call terraform, "destroy")

deploy: init
	@echo "Deploying ${TF_VAR_service_name} branch ${TF_VAR_branch}"
	@$(call terraform_apply)

output:
	@:$(call check_defined, name, name)
	@$(call terraform_output, ${name})

check:
	@cd src && cargo check

lint: check
	@cd src && cargo clippy

test:
	aws lambda invoke --function-name $(shell $(call terraform_output, lambda_arn)) output.json