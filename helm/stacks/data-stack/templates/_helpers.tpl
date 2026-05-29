{{- define "data-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "data-stack.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "data-stack.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/name: {{ include "data-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "data-stack.awsEnv" -}}
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ required "backups.r2.existingSecret is required" .Values.backups.r2.existingSecret | quote }}
      key: {{ .Values.backups.r2.accessKeyIdKey | quote }}
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ required "backups.r2.existingSecret is required" .Values.backups.r2.existingSecret | quote }}
      key: {{ .Values.backups.r2.secretAccessKeyKey | quote }}
- name: AWS_DEFAULT_REGION
  value: {{ .Values.backups.r2.region | quote }}
- name: R2_ENDPOINT
  value: {{ required "backups.r2.endpoint is required" .Values.backups.r2.endpoint | quote }}
- name: R2_BUCKET
  value: {{ required "backups.r2.bucket is required" .Values.backups.r2.bucket | quote }}
- name: R2_PREFIX
  value: {{ .Values.backups.r2.prefix | quote }}
{{- end -}}

{{- define "data-stack.uploadContainer" -}}
- name: upload-to-r2
  image: "{{ .Values.backups.uploader.image.repository }}:{{ .Values.backups.uploader.image.tag }}"
  imagePullPolicy: {{ .Values.backups.uploader.image.pullPolicy }}
  command:
    - /bin/sh
    - -ec
    - |
      BACKUP_DATE="$(date -u +%Y%m%dT%H%M%SZ)"
      test -n "$(find /backup -type f -print -quit)"
      aws --endpoint-url "${R2_ENDPOINT}" s3 sync /backup "s3://${R2_BUCKET}/${R2_PREFIX}/${COMPONENT}/${BACKUP_DATE}/" --only-show-errors
  volumeMounts:
    - name: backup
      mountPath: /backup
{{- end -}}
