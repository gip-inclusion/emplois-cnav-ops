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
Django environment common to every pod (backoffice, api, migrations job)
The database user/password differ per pod and are set by each template
*/}}
{{- define "api-relay.djangoCommonEnv" -}}
- name: DJANGO_ENVIRONMENT
  value: "PROD"
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
- name: DJANGO_INTEROPS_BASE_URL
  value: {{ required "interops.baseUrl must be set (SOPS values-<env>.enc.yaml)" .Values.interops.baseUrl | quote }}
- name: DJANGO_INTEROPS_ORGANIZATION_CODE
  value: {{ required "interops.organizationCode must be set (SOPS values-<env>.enc.yaml)" .Values.interops.organizationCode | quote }}
- name: DJANGO_INTEROPS_ORGANIZATION_LABEL
  value: {{ required "interops.organizationLabel must be set (SOPS values-<env>.enc.yaml)" .Values.interops.organizationLabel | quote }}
- name: DJANGO_INTEROPS_SUBJECT_ID
  value: {{ required "interops.subjectId must be set (SOPS values-<env>.enc.yaml)" .Values.interops.subjectId | quote }}
- name: DJANGO_INTEROPS_IDENTITY_PATH
  value: {{ required "interops.identityPath must be set (SOPS values-<env>.enc.yaml)" .Values.interops.identityPath | quote }}
{{- end }}

{{/*
Backoffice-specific Django env (backoffice deployment + migrations job)
*/}}
{{- define "api-relay.backofficeEnv" -}}
- name: DJANGO_SERVICE
  value: "BACKOFFICE"
- name: DJANGO_ALLOWED_HOSTS
  value: {{ .Values.backoffice.host | quote }}
- name: DJANGO_CSRF_TRUSTED_ORIGINS
  value: {{ printf "https://%s" .Values.backoffice.host | quote }}
- name: DJANGO_AUTHENTIK_LOGOUT_URL
  value: {{ .Values.backoffice.authentikLogoutUrl | quote }}
{{- end }}

{{/*
Health probes shared by both components
uWSGI takes ~20s to load and the first (cold) request can exceed 1s, so a startupProbe gives room before
the liveness/readiness take over
The kubelet probes the pod by IP: the Host header presents the served hostname so the request complies with
Django's ALLOWED_HOSTS
*/}}
{{- define "api-relay.probes" -}}
startupProbe:
  httpGet:
    path: /healthcheck/live/
    port: http
    httpHeaders:
      - name: Host
        value: {{ .host }}
  periodSeconds: 3
  timeoutSeconds: 5
  failureThreshold: 20
livenessProbe:
  httpGet:
    path: /healthcheck/live/
    port: http
    httpHeaders:
      - name: Host
        value: {{ .host }}
  periodSeconds: 10
  timeoutSeconds: 3
readinessProbe:
  httpGet:
    path: /healthcheck/ready/
    port: http
    httpHeaders:
      - name: Host
        value: {{ .host }}
  periodSeconds: 10
  timeoutSeconds: 3
{{- end }}

{{/*
API-specific Django env (api deployment)
*/}}
{{- define "api-relay.apiEnv" -}}
- name: DJANGO_SERVICE
  value: "API"
- name: DJANGO_ALLOWED_HOSTS
  value: {{ .Values.api.host | quote }}
# Only the API service needs the token hash; the pod never holds the plaintext
- name: DJANGO_HASHED_API_TOKEN
  valueFrom:
    secretKeyRef:
      name: api-relay-api-token
      key: hashed_token
{{- end }}
