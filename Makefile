# RHDH Must-Gather Tool Makefile

# Variables
VERSION ?= 1.9.0
GIT_SHA := $(shell git describe --no-match --always --abbrev=9 --dirty --broken 2>/dev/null || echo unknown)
RHDH_MUST_GATHER_VERSION := $(VERSION)-$(GIT_SHA)
SCRIPT ?= rhdh
IMAGE_NAME ?= rhdh-community/rhdh-must-gather
IMAGE_TAG ?= next
REGISTRY ?= quay.io
FULL_IMAGE_NAME ?= $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)
LOG_LEVEL ?= info
OPTS ?= ## Additional options to pass to must-gather (e.g., --with-heap-dumps --with-secrets)
CONTAINER_TOOL ?= podman
BUILD_ARGS ?=
LABELS ?=
TOOLS_DIR ?= ./bin

# BATS test configuration
BATS_VERSION ?= 1.13.0
BATS_CORE_URL := https://github.com/bats-core/bats-core/archive/refs/tags/v$(BATS_VERSION).tar.gz
BATS_BIN := $(TOOLS_DIR)/bats-core-$(BATS_VERSION)/bin/bats
TEST_RESULTS_DIR ?= ./test-results
TESTS_OPTIONS ?= --timing --print-output-on-failure --report-formatter junit --output "$(TEST_RESULTS_DIR)"

TESTS_DIR := ./tests

default: test-container-all

# Build targets
.PHONY: build
build: ## Build the must-gather container image
	@echo "Building must-gather image..."
	$(CONTAINER_TOOL) build $(BUILD_ARGS) $(if $(LABELS),$(LABELS)) --build-arg RHDH_MUST_GATHER_VERSION=$(RHDH_MUST_GATHER_VERSION) -t $(IMAGE_NAME):$(IMAGE_TAG) .
	@echo "Image built: $(IMAGE_NAME):$(IMAGE_TAG)"

.PHONY: build-push
build-push: build ## Build and push the image to registry
	@echo "Tagging image for registry..."
	$(CONTAINER_TOOL) tag $(IMAGE_NAME):$(IMAGE_TAG) $(FULL_IMAGE_NAME)
	@echo "Pushing image to registry..."
	$(CONTAINER_TOOL) push $(FULL_IMAGE_NAME)
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
	BASE_COLLECTION_PATH=./test-output \
	LOG_LEVEL=$(LOG_LEVEL) \
	RHDH_MUST_GATHER_VERSION=$(RHDH_MUST_GATHER_VERSION) \
	./collection-scripts/must_gather $(OPTS)

.PHONY: test-local-script
test-local-script: test-output ## Test the specified script (set the SCRIPT var)
	@echo "Testing gather-${SCRIPT} must-gather script locally..."
	@if ! command -v kubectl >/dev/null 2>&1; then \
		echo "Error: kubectl not found. Please install kubectl to test."; \
		exit 1; \
	fi
	@echo "Running local test (requires cluster access)..."
	BASE_COLLECTION_PATH=./test-output \
	LOG_LEVEL=$(LOG_LEVEL)\
	RHDH_MUST_GATHER_VERSION=$(RHDH_MUST_GATHER_VERSION) \
	./collection-scripts/gather_${SCRIPT}

.PHONY: test-container-all
test-container-all: test-output ## Test using container (requires podman)
	@echo "Testing must-gather in container..."
	podman run --rm \
		-v $(HOME)/.kube:/home/must-gather/.kube:ro \
		-v $(PWD)/test-output:/must-gather \
		-e LOG_LEVEL=$(LOG_LEVEL) \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		$(OPTS)

# ============================================================================
# BATS Unit Test Targets
# ============================================================================

.PHONY: test-results
test-results: ## Create test results directory
	@mkdir -p $(TEST_RESULTS_DIR)

.PHONY: test-setup
test-setup: test-results ## Download and setup BATS testing framework
	@echo "Setting up BATS testing framework..."
	@if [ ! -d "$(TOOLS_DIR)/bats-core-$(BATS_VERSION)" ]; then \
		echo "Downloading BATS v$(BATS_VERSION)..."; \
		mkdir -p "$(TOOLS_DIR)/bats-core-$(BATS_VERSION)"; \
		curl -sL $(BATS_CORE_URL) | tar xz -C "$(TOOLS_DIR)/bats-core-$(BATS_VERSION)" --strip-components=1; \
		echo "BATS installed successfully"; \
	else \
		echo "BATS $(BATS_VERSION) already installed: $(TOOLS_DIR)/bats-core-$(BATS_VERSION)"; \
	fi

.PHONY: test
test: test-setup ## Run all BATS unit tests
	@echo "Running BATS unit tests..."
	@$(BATS_BIN) $(TESTS_OPTIONS) $(TESTS_DIR)/*.bats

# ============================================================================
# E2E Test Targets
# ============================================================================

.PHONY: test-e2e
test-e2e: ## Run E2E tests against a K8s cluster (requires Kind or similar)
	@echo "Running E2E tests with image: $(FULL_IMAGE_NAME)..."
	@./tests/e2e/run-e2e-tests.sh "$(FULL_IMAGE_NAME)" "$(OPTS)"

# ============================================================================
# Cleanup Targets
# ============================================================================

.PHONY: clean
clean: ## Remove built images and test output
	@echo "Cleaning up..."
	-podman rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	-podman rmi $(FULL_IMAGE_NAME) 2>/dev/null || true
	-rm -rf ./test-output
	@echo "Cleanup complete"


.PHONY: test-clean
test-clean: ## Remove BATS framework and test results
	@echo "Cleaning up test artifacts..."
	-rm -rf "$(TOOLS_DIR)/bats-core-$(BATS_VERSION)"
	-rm -rf "$(TEST_RESULTS_DIR)"
	@echo "Test cleanup complete"

.PHONY: tools-clean
tools-clean: ## Remove tools directory
	@echo "Cleaning up tools..."
	-rm -rf "$(TOOLS_DIR)"
	@echo "Tools cleanup complete"

.PHONY: clean-all
clean-all: clean test-clean tools-clean ## Remove all generated artifacts (images, test output, BATS, tools)
	@echo "Full cleanup complete"

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
	@if ! command -v yq >/dev/null 2>&1; then \
		echo "Error: yq command not found. Please install yq."; \
		exit 1; \
	fi
	@if ! command -v jq >/dev/null 2>&1; then \
		echo "Error: jq command not found. Please install jq."; \
		exit 1; \
	fi
	@if ! command -v kubectl >/dev/null 2>&1; then \
		echo "Error: kubectl command not found."; \
		exit 1; \
	fi
	@# Generate random namespace
	@TIMESTAMP=$$(date +%s); \
	NAMESPACE="rhdh-must-gather-$$TIMESTAMP"; \
	OUTPUT_FILE="rhdh-must-gather-output.k8s.$$TIMESTAMP.tar.gz"; \
	TMP_FILE=$$(mktemp); \
	echo "Preparing must-gather resources in namespace: $$NAMESPACE"; \
	cp deploy/kubernetes-job.yaml $$TMP_FILE; \
	yq eval -i '(select(.kind == "Namespace") | .metadata.name) = "'$$NAMESPACE'"' $$TMP_FILE; \
	yq eval -i '(select(.kind == "ServiceAccount") | .metadata.namespace) = "'$$NAMESPACE'"' $$TMP_FILE; \
	yq eval -i '(select(.kind == "ClusterRoleBinding") | .subjects[0].namespace) = "'$$NAMESPACE'"' $$TMP_FILE; \
	yq eval -i '(select(.kind == "PersistentVolumeClaim") | .metadata.namespace) = "'$$NAMESPACE'"' $$TMP_FILE; \
	yq eval -i '(select(.kind == "Job") | .metadata.namespace) = "'$$NAMESPACE'"' $$TMP_FILE; \
	yq eval -i '(select(.kind == "Job") | .spec.template.spec.containers[0].image) = "$(FULL_IMAGE_NAME)"' $$TMP_FILE; \
	yq eval -i '(select(.kind == "Pod") | .metadata.namespace) = "'$$NAMESPACE'"' $$TMP_FILE; \
	if [ -n "$(OPTS)" ]; then \
		ARGS_JSON=$$(echo "$(OPTS)" | xargs -n1 | jq -R . | jq -s .); \
		yq eval -i "(select(.kind == \"Job\") | .spec.template.spec.containers[0].args) = $$ARGS_JSON" $$TMP_FILE; \
	fi; \
	echo "Creating must-gather resources..."; \
	kubectl apply -f $$TMP_FILE; \
	echo ""; \
	echo "Waiting for job to complete (timeout: 600s)..."; \
	if kubectl -n $$NAMESPACE wait --for=condition=complete job/rhdh-must-gather --timeout=600s 2>&1; then \
		echo "Job completed successfully"; \
	else \
		echo "Error: Job did not complete within timeout"; \
		echo ""; \
		echo "Job logs:"; \
		kubectl -n $$NAMESPACE logs job/rhdh-must-gather --tail=50 || true; \
		exit 1; \
	fi; \
	echo ""; \
	echo "Waiting for data retriever pod to be ready (timeout: 60s)..."; \
	if kubectl -n $$NAMESPACE wait --for=condition=ready pod/rhdh-must-gather-data-retriever --timeout=60s 2>&1; then \
		echo "Data retriever pod is ready"; \
	else \
		echo "Error: Data retriever pod did not become ready within timeout"; \
		echo ""; \
		kubectl -n $$NAMESPACE describe pod/rhdh-must-gather-data-retriever || true; \
		exit 1; \
	fi; \
	echo ""; \
	echo "Pulling must-gather data from pod..."; \
	kubectl -n $$NAMESPACE exec rhdh-must-gather-data-retriever -- tar czf - -C /data . > $$OUTPUT_FILE; \
	echo ""; \
	echo "Cleaning up resources..."; \
	kubectl delete -f $$TMP_FILE --wait=false 2>/dev/null || true; \
	rm -f $$TMP_FILE; \
	echo ""; \
	echo "✓ Must-gather data saved to: $$OUTPUT_FILE"; \
	echo ""; \
	echo "To extract the data, run:"; \
	echo "  tar xzf $$OUTPUT_FILE"

.PHONY: help
help: ## Show this help message
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {sub("\\\\n",sprintf("\n%22c"," "), $$2);printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Variables:"
	@echo "  VERSION       - Must-gather version (default: $(VERSION))"
	@echo "  RHDH_MUST_GATHER_VERSION - Full version with git SHA (computed: $(RHDH_MUST_GATHER_VERSION))"
	@echo "  REGISTRY      - Container registry (default: $(REGISTRY))"
	@echo "  IMAGE_NAME    - Container image name (default: $(IMAGE_NAME))"
	@echo "  IMAGE_TAG     - Container image tag (default: $(IMAGE_TAG))"
	@echo "  LOG_LEVEL     - Log level (default: $(LOG_LEVEL))"
	@echo "  OPTS          - Additional must-gather options (e.g., --with-heap-dumps --with-secrets)"
	@echo "  SCRIPT        - Script name for test-local-script (default: $(SCRIPT))"
	@echo "  BATS_VERSION  - BATS testing framework version (default: $(BATS_VERSION))"
	@echo ""
	@echo "Examples:"
	@echo "  make test                                          # Run all unit tests"
	@echo "  make test-e2e FULL_IMAGE_NAME=quay.io/org/img:tag  # Run E2E tests on Kind"
	@echo "  make test-local-all OPTS=\"--with-heap-dumps\""
	@echo "  make test-container-all OPTS=\"--with-secrets --with-heap-dumps\""
	@echo "  make openshift-test OPTS=\"--with-heap-dumps --namespaces my-ns\""
