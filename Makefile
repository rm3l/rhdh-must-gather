# RHDH Must-Gather Tool Makefile

# Variables
IMAGE_NAME ?= rhdh-must-gather
IMAGE_TAG ?= latest
REGISTRY ?= quay.io/asoro
FULL_IMAGE_NAME = $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

# Build targets
.PHONY: build
build:
	@echo "Building must-gather image..."
	podman build -t $(IMAGE_NAME):$(IMAGE_TAG) .
	@echo "Image built: $(IMAGE_NAME):$(IMAGE_TAG)"

.PHONY: build-push
build-push: build
	@echo "Tagging image for registry..."
	podman tag $(IMAGE_NAME):$(IMAGE_TAG) $(FULL_IMAGE_NAME)
	@echo "Pushing image to registry..."
	podman push $(FULL_IMAGE_NAME)
	@echo "Image pushed: $(FULL_IMAGE_NAME)"

test-output:
	@mkdir -p ./test-output

.PHONY: test-local
test-local: test-output
	@echo "Testing must-gather script locally..."
	@if ! command -v kubectl >/dev/null 2>&1; then \
		echo "Error: kubectl not found. Please install kubectl to test."; \
		exit 1; \
	fi
	@echo "Running local test (requires cluster access)..."
	MUST_GATHER_DIR=./test-output ./collection/gather

.PHONY: test-container
test-container: test-output
	@echo "Testing must-gather in container..."
	podman run --rm \
		-v $(HOME)/.kube:/home/must-gather/.kube:ro \
		-v $(PWD)/test-output:/must-gather \
		$(IMAGE_NAME):$(IMAGE_TAG)

.PHONY: clean
clean:
	@echo "Cleaning up..."
	-podman rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null || true
	-podman rmi $(FULL_IMAGE_NAME) 2>/dev/null || true
	-rm -rf ./test-output
	@echo "Cleanup complete"

.PHONY: openshift-test
openshift-test:
	@echo "Testing with oc adm must-gather..."
	@if ! command -v oc >/dev/null 2>&1; then \
		echo "Error: oc command not found. Please install OpenShift CLI."; \
		exit 1; \
	fi
	oc adm must-gather --image=$(FULL_IMAGE_NAME)

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  build         - Build the must-gather container image"
	@echo "  build-push    - Build and push the image to registry"
	@echo "  test-local    - Test the script locally (requires kubectl)"
	@echo "  test-container- Test using container (requires podman)"
	@echo "  openshift-test- Test using oc adm must-gather"
	@echo "  clean         - Remove built images and test output"
	@echo "  help          - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  IMAGE_NAME    - Container image name (default: $(IMAGE_NAME))"
	@echo "  IMAGE_TAG     - Container image tag (default: $(IMAGE_TAG))"
	@echo "  REGISTRY      - Container registry (default: $(REGISTRY))"