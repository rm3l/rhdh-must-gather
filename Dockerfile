FROM quay.io/openshift/origin-must-gather:4.20

ENV RHDH_MUST_GATHER_VERSION=0.1.0

# Must-gather image for Red Hat Developer Hub (RHDH)
LABEL name="rhdh-must-gather" \
      vendor="Red Hat" \
      version="$RHDH_MUST_GATHER_VERSION" \
      summary="Red Hat Developer Hub (RHDH) must-gather tool" \
      description="Collects diagnostic information from RHDH deployments on Kubernetes and OpenShift clusters"

# Save original gather script
RUN mv /usr/bin/gather /usr/bin/gather_original

# Install yq
RUN curl -sSLo- https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64.tar.gz | tar xz \
    && mv -f yq_linux_amd64 /usr/local/bin/yq \
    && yq --version

# Install Helm
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    && chmod 700 get_helm.sh \
    && ./get_helm.sh \
    && rm get_helm.sh \
    && helm version

# Use our gather script in place of the original one
# Copy collection scripts
COPY collection-scripts/* /usr/bin/

RUN mv /usr/bin/must_gather /usr/bin/gather

ENTRYPOINT exec /usr/bin/gather
