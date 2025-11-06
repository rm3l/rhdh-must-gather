# RHDH Must-Gather Tool Makefile

# Variables
SCRIPT ?= rhdh
IMAGE_NAME ?= rhdh-must-gather
IMAGE_TAG ?= main
REGISTRY ?= ghcr.io/rm3l
FULL_IMAGE_NAME = $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)
LOG_LEVEL ?= info
OPTS ?= ## Additional options to pass to must-gather (e.g., --with-heap-dumps --with-secrets)

default: test-container-all

# Build targets
.PHONY: build
build: ## Build the must-gather container image
	@echo "Building must-gather image..."
	podman build -t $(IMAGE_NAME):$(IMAGE_TAG) .
	@echo "Image built: $(IMAGE_NAME):$(IMAGE_TAG)"

.PHONY: build-push
build-push: build ## Build and push the image to registry
	@echo "Tagging image for registry..."
	podman tag $(IMAGE_NAME):$(IMAGE_TAG) $(FULL_IMAGE_NAME)
	@echo "Pushing image to registry..."
	podman push $(FULL_IMAGE_NAME)
	@echo "Image pushed: $(FULL_IMAGE_NAME)"

test-output:
	@mkdir -p ./test-output

.PHONY: test-local-all
test-local-all: test-output ## Test the script locally (requires kubectl)
	@echo "Testing must-gather script locally..."
	@if ! command -v kubectl >/dev/null 2>&1; then \
		echo "Error: kubectl not found. Please install kubectl to test."; \
		exit 1; \
	fi
	@echo "Running local test (requires cluster access)..."
	BASE_COLLECTION_PATH=./test-output LOG_LEVEL=$(LOG_LEVEL) ./collection-scripts/must_gather $(OPTS)

.PHONY: test-local-script
test-local-script: test-output ## Test the specified script (set the SCRIPT var)
	@echo "Testing gather-${SCRIPT} must-gather script locally..."
	@if ! command -v kubectl >/dev/null 2>&1; then \
		echo "Error: kubectl not found. Please install kubectl to test."; \
		exit 1; \
	fi
	@echo "Running local test (requires cluster access)..."
	BASE_COLLECTION_PATH=./test-output LOG_LEVEL=$(LOG_LEVEL) ./collection-scripts/gather_${SCRIPT}

.PHONY: test-container-all
test-container-all: test-output ## Test using container (requires podman)
	@echo "Testing must-gather in container..."
	podman run --rm \
		-v $(HOME)/.kube:/home/must-gather/.kube:ro \
		-v $(PWD)/test-output:/must-gather \
		-e LOG_LEVEL=$(LOG_LEVEL) \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		$(OPTS)

.PHONY: clean
clean: ## Remove built images and test output
	@echo "Cleaning up..."
	-podman rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	-podman rmi $(FULL_IMAGE_NAME) 2>/dev/null || true
	-rm -rf ./test-output
	@echo "Cleanup complete"

.PHONY: openshift-test
openshift-test: ## Test using the 'oc adm must-gather' command
	@echo "Testing with oc adm must-gather..."
	@if ! command -v oc >/dev/null 2>&1; then \
		echo "Error: oc command not found. Please install OpenShift CLI."; \
		exit 1; \
	fi
	@if [ -z "$(OPTS)" ]; then \
		oc adm must-gather --image=$(FULL_IMAGE_NAME); \
	else \
		oc adm must-gather --image=$(FULL_IMAGE_NAME) -- /usr/bin/gather $(OPTS); \
	fi

.PHONY: k8s-test
k8s-test: ## Test on a non-OCP K8s cluster
	@echo "Testing against a regular K8s cluster..."
	@if ! command -v envsubst >/dev/null 2>&1; then \
		echo "Error: envsubst command not found."; \
		exit 1; \
	fi
	@if ! command -v kubectl >/dev/null 2>&1; then \
		echo "Error: kubectl command not found."; \
		exit 1; \
	fi
	@if ! kubectl get namespace rhdh-must-gather &> /dev/null; then \
		kubectl create namespace rhdh-must-gather; \
	fi
	@# Convert OPTS to YAML array format (e.g., ["--with-heap-dumps", "--with-secrets"])
	@if [ -z "$(OPTS)" ]; then \
		ARGS_YAML="[]"; \
	else \
		ARGS_YAML=$$(echo "$(OPTS)" | awk 'BEGIN{printf "["} {for(i=1;i<=NF;i++) printf "\"%s\"%s", $$i, (i<NF?", ":"")} END{print "]"}'); \
	fi; \
	JOB_ID=$(shell date +%s) FULL_IMAGE_NAME=$(FULL_IMAGE_NAME) NS=rhdh-must-gather ARGS="$$ARGS_YAML" envsubst < deploy/kubernetes-job.yaml \
		| kubectl apply -f -

.PHONY: help
help: ## Show this help message
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {sub("\\\\n",sprintf("\n%22c"," "), $$2);printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Variables:"
	@echo "  REGISTRY      - Container registry (default: $(REGISTRY))"
	@echo "  IMAGE_NAME    - Container image name (default: $(IMAGE_NAME))"
	@echo "  IMAGE_TAG     - Container image tag (default: $(IMAGE_TAG))"
	@echo "  LOG_LEVEL     - Log level (default: $(LOG_LEVEL))"
	@echo "  OPTS          - Additional must-gather options (e.g., --with-heap-dumps --with-secrets)"
	@echo "  SCRIPT        - Script name for test-local-script (default: $(SCRIPT))"
	@echo ""
	@echo "Examples:"
	@echo "  make test-local-all OPTS=\"--with-heap-dumps\""
	@echo "  make test-container-all OPTS=\"--with-secrets --with-heap-dumps\""
	@echo "  make openshift-test OPTS=\"--with-heap-dumps --namespaces my-ns\""
