FROM registry.redhat.io/ubi8/ubi:latest

# Must-gather image for Red Hat Developer Hub (RHDH)
LABEL name="rhdh-must-gather" \
      vendor="Red Hat" \
      version="1.0.0" \
      release="1" \
      summary="Red Hat Developer Hub must-gather tool" \
      description="Collects diagnostic information from RHDH deployments on Kubernetes and OpenShift clusters"

# Install required packages
RUN dnf update -y && \
    dnf install -y \
        curl \
        wget \
        tar \
        gzip \
        jq \
        which \
        bash \
        coreutils \
    && dnf clean all \
    && rm -rf /var/cache/yum

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# Install oc client (OpenShift CLI)
RUN curl -L https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/linux/oc.tar.gz \
    | tar -xzC /usr/local/bin/ \
    && chmod +x /usr/local/bin/oc

# Install Helm
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    && chmod 700 get_helm.sh \
    && ./get_helm.sh \
    && rm get_helm.sh

# Create must-gather user and directories
RUN useradd -r -u 1001 -g 0 must-gather \
    && mkdir -p /must-gather \
    && chown -R 1001:0 /must-gather \
    && chmod -R g+w /must-gather

# Copy collection scripts
COPY collection/ /usr/local/bin/
RUN chmod +x /usr/local/bin/gather

# Copy licenses
COPY licenses/ /licenses/

# Set working directory
WORKDIR /must-gather

# Use non-root user
USER 1001

# Set environment variables
ENV MUST_GATHER_DIR=/must-gather
ENV PATH="/usr/local/bin:${PATH}"

# Default command
CMD ["/usr/local/bin/gather"]