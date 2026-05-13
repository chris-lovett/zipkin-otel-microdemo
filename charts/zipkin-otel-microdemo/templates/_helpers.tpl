{{- define "zipkin-otel-microdemo.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "zipkin-otel-microdemo.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "zipkin-otel-microdemo.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "zipkin-otel-microdemo.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "zipkin-otel-microdemo.appImage" -}}
{{- $registry := .Values.global.imageRegistry -}}
{{- $repo := .repository -}}
{{- $tag := .tag | default "latest" -}}
{{- if $registry -}}
{{ printf "%s/%s:%s" $registry $repo $tag }}
{{- else -}}
{{ printf "%s:%s" $repo $tag }}
{{- end -}}
{{- end -}}
