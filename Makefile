.PHONY: validate

help:
	@echo "The list of commands for local development:\n"
	@echo "  validate      Validates the cloudformation template via awscli"

validate:
	aws cloudformation validate-template --template-body file://ansible/files/cloudformation.json
