PROJECT := cookiecutter-nodejs
VERSION := 0.2.0
ROOT_DIR := $(shell git rev-parse --show-toplevel)
MAKEFILE_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: reset
reset: clean
	@rm -f Brewfile.lock.json
	@rm -rf node_modules
	@rm -f .git/hooks/commit-msg

.PHONY: clean
clean:
	@npm run clean

.PHONY: install
install: node_modules/.package-lock.json
install: .git/hooks/commit-msg
install: Brewfile.lock.json

Brewfile.lock.json: Brewfile
	@brew bundle

node_modules/.package-lock.json: package.json
	@npm install

.git/hooks/commit-msg: .pre-commit-config.yaml
	@pre-commit install --hook-type commit-msg

.PHONY: format
format:
	@npm run format

.PHONY: lint
lint: --lint-node --lint-docker

--lint-node:
	@npm run lint

--lint-docker:
	@docker run --rm -i hadolint/hadolint:latest < $(ROOT_DIR)/Dockerfile

.PHONY: scan
scan: --scan-dockle --scan-trivy

# scan docker image for best practices
--scan-dockle: DOCKLE_IGNORES = $(shell awk 'NF {print $1}' $(ROOT_DIR)/.dockleignore | paste -s -d, -)
--scan-dockle: build
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
--scan-trivy: build
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

.PHONY: build
build: DOCKER_CONTENT_TRUST=1
build:
	@docker build \
		-t $(PROJECT) \
		-t $(PROJECT):$(VERSION) \
		--build-arg APP_NAME="$(PROJECT)" \
		--build-arg APP_VERSION="$(VERSION)" \
		--build-arg APP_REVISION="$(shell git rev-parse --short HEAD)" \
		.

.PHONY: start
start: build
	@docker run $(PROJECT)

.PHONY: release
release: lint scan version build
	@git push --follow-tags

.PHONY: version
version:
	@cz bump --yes

.gitignore:
	@git ignore-io homebrew node > .gitignore
