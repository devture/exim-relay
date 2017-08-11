DOCKER_REGISTRY = industrieco
IMAGE_NAME = exim-relay
IMAGE_VERSION = latest
IMAGE_TAG = $(DOCKER_REGISTRY)/$(IMAGE_NAME):$(IMAGE_VERSION)

WORKING_DIR := $(shell pwd)

.DEFAULT_GOAL := help

# List of targets that are commands, not files
.PHONY: release push build

release:: build push ## Builds and pushes the docker image to the registry

push:: ## Pushes the docker image to the registry
		@docker push $(IMAGE_TAG)

build:: ## Builds the docker image locally
		@docker build -f Dockerfile -t $(IMAGE_TAG) $(WORKING_DIR)

# A help target including self-documenting targets (see the awk statement)
define HELP_TEXT
             _                        __           
  ___  _  __(_)___ ___     ________  / /___ ___  __
 / _ \\| |/_/ / __ `__ \\   / ___/ _ \\/ / __ `/ / / /
/  __/>  </ / / / / / /  / /  /  __/ / /_/ / /_/ / 
\\___/_/|_/_/_/ /_/ /_/  /_/   \\___/_/\\__,_/\\__, /  
                                          /____/   

Usage: make [TARGET]... [MAKEVAR1=SOMETHING]...

Available targets:
endef
export HELP_TEXT
help: ## This help target
	@echo "$$HELP_TEXT"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / \
		{printf "\033[36m%-30s\033[0m  %s\n", $$1, $$2}' $(MAKEFILE_LIST)
