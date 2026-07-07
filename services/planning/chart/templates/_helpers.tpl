{{- define "planning.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "planning.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "planning.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "planning.labels" -}}
app.kubernetes.io/name: {{ include "planning.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: devhub-campus
app.kubernetes.io/managed-by: Helm
{{- range $k, $v := .Values.extraLabels }}
{{ $k }}: {{ $v }}
{{- end }}
{{- end -}}

{{/* Sélecteur minimal stable : name + instance uniquement (le selector est immuable). */}}
{{- define "planning.selectorLabels" -}}
app.kubernetes.io/name: {{ include "planning.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
