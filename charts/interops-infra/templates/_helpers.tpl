{{/*
Namespace name based on environment
*/}}
{{- define "interops.namespace" -}}
interops-{{ .Values.environment }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "interops.labels" -}}
app.kubernetes.io/part-of: emplois-cnav
environment: {{ .Values.environment }}
{{- end }}
