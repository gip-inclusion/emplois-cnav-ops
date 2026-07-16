{{/*
Expand the name of the chart
*/}}
{{- define "api-relay.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name
*/}}
{{- define "api-relay.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label
*/}}
{{- define "api-relay.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "api-relay.labels" -}}
helm.sh/chart: {{ include "api-relay.chart" . }}
{{ include "api-relay.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: emplois-cnav
{{- end }}

{{/*
Selector labels
*/}}
{{- define "api-relay.selectorLabels" -}}
app.kubernetes.io/name: {{ include "api-relay.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "api-relay.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "api-relay.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Django environment shared by the backoffice deployment and the migrations job
The database credentials (user/password) differ between the two and are set by each template
*/}}
{{- define "api-relay.djangoCommonEnv" -}}
- name: DJANGO_ENVIRONMENT
  value: "PROD"
- name: DJANGO_SERVICE
  value: "BACKOFFICE"
- name: DJANGO_ALLOWED_HOSTS
  value: {{ .Values.backoffice.host | quote }}
- name: DJANGO_CSRF_TRUSTED_ORIGINS
  value: {{ printf "https://%s" .Values.backoffice.host | quote }}
- name: DJANGO_AUTHENTIK_LOGOUT_URL
  value: {{ .Values.backoffice.authentikLogoutUrl | quote }}
- name: DJANGO_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: api-relay-django
      key: secret_key
- name: DJANGO_SECRET_KEY_FALLBACKS
  valueFrom:
    secretKeyRef:
      name: api-relay-django
      key: secret_key_fallbacks
- name: DJANGO_DB_HOST
  valueFrom:
    secretKeyRef:
      name: api-relay-database
      key: host
- name: DJANGO_DB_PORT
  valueFrom:
    secretKeyRef:
      name: api-relay-database
      key: port
- name: DJANGO_DB_NAME
  valueFrom:
    secretKeyRef:
      name: api-relay-database
      key: name
{{- end }}
