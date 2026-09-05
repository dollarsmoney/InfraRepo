{{- define "marketplace.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "marketplace.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "marketplace.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "marketplace.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "marketplace.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
marketplace.io/environment: {{ .Values.environment }}
{{- end -}}

{{- define "marketplace.selectorLabels" -}}
app.kubernetes.io/name: {{ include "marketplace.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "marketplace.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "marketplace.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "marketplace.configMapName" -}}
{{- printf "%s-config" (include "marketplace.fullname" .) -}}
{{- end -}}

{{/* Fully qualified image reference, e.g. ghcr.io/org/repo-backend:sha-abc1234 */}}
{{- define "marketplace.image" -}}
{{- printf "%s/%s:%s" .root.Values.image.registry .component.image.repository (required "an image tag is required" .component.image.tag) -}}
{{- end -}}
