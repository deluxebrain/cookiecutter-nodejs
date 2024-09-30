PROJECT := cookiecutter-nodejs
VERSION := 0.1.0
ROOT_DIR := $(shell git rev-parse --show-toplevel)
MAKEFILE_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))

# run after cloning repo
setup: --setup_git_hooks
setup: --setup_install_packages

# install pre-commit git hooks
--setup_git_hooks:
	@git fetch origin --tags
	@pre-commit install --hook-type commit-msg

--setup_install_packages:
	@brew bundle --no-lock
	@npm install

start: build
	@docker run $(PROJECT)

clean:
	@npm run clean

format:
	@npm run format

lint: lint-node lint-docker

lint-node:
	@npm run lint

lint-docker:
	@docker run --rm -i hadolint/hadolint:latest < $(ROOT_DIR)/Dockerfile

scan: scan-dockle scan-trivy

# scan docker image for best practices
scan-dockle: DOCKLE_IGNORES = $(shell awk 'NF {print $1}' $(ROOT_DIR)/.dockleignore | paste -s -d, -)
scan-dockle: build
	@docker run --rm \
		--env DOCKER_CONTENT_TRUST=1 \
		--env DOCKLE_IGNORES=$(DOCKLE_IGNORES) \
		-v /var/run/docker.sock:/var/run/docker.sock \
		goodwithtech/dockle:latest \
			--timeout 10m \
			--exit-code 1 \
			--exit-level warn \
			$(PROJECT):$(VERSION)

# scan OS and app dependencies for vulnerabilities
scan-trivy: build
	@docker run --rm \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v $${XDG_CACHE_HOME:-$$HOME/.cache}:/root/.cache/ \
		aquasec/trivy:latest \
		image \
			--timeout 10m \
			--ignore-unfixed \
			--exit-code 1 \
			--severity HIGH,CRITICAL \
			$(PROJECT):$(VERSION)

build: DOCKER_CONTENT_TRUST=1
build:
	@docker build \
		-t $(PROJECT) \
		-t $(PROJECT):$(VERSION) \
		--build-arg APP_NAME="$(PROJECT)" \
		--build-arg APP_VERSION="$(VERSION)" \
		--build-arg APP_REVISION="$(shell git rev-parse --short HEAD)" \
		.

release: lint scan version build
	@git push --follow-tags

version:
	@cz bump --yes
