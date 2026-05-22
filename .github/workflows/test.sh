#!/bin/bash

helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add qdrant https://qdrant.github.io/qdrant-helm
helm repo update

helm dependency build helm/stacks/data-stack

helm lint helm/stacks/data-stack \
  -f helm/stacks/data-stack/values.yaml

helm template data-stack helm/stacks/data-stack \
  -n skala3-finalproj-class2-team7 \
  -f helm/stacks/data-stack/values.yaml

helm template loki grafana/loki \
  -n skala3-finalproj-class2-team7 \
  -f observability/logging/loki-values.yaml

helm template alloy grafana/alloy \
  -n skala3-finalproj-class2-team7 \
  -f observability/logging/alloy-values.yaml

helm template monitoring prometheus-community/kube-prometheus-stack \
  -n skala3-finalproj-class2-team7 \
  -f observability/monitoring/values.yaml
