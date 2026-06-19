# Tracing

This directory deploys the first OpenTelemetry tracing layer for the team7 namespace.

Flow:

```text
instrumented app -> otel-collector:4317/4318 -> tempo:4317 -> Grafana Tempo datasource
```

Application OTLP endpoints inside the cluster:

- gRPC: `http://otel-collector.skala3-finalproj-class2-team7.svc.cluster.local:4317`
- HTTP: `http://otel-collector.skala3-finalproj-class2-team7.svc.cluster.local:4318`

Recommended service environment variables:

```text
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=none
OTEL_LOGS_EXPORTER=none
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.skala3-finalproj-class2-team7.svc.cluster.local:4317
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=dev
```

Set a different `OTEL_SERVICE_NAME` per process, for example `rag-deploy`,
`ingestion-api`, `ingestion-worker`, `bff-server`, and `auth-server`.
