{{- define "notif.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "notif.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "notif.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "notif.labels" -}}
app.kubernetes.io/name: {{ include "notif.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: devhub-campus
app.kubernetes.io/managed-by: Helm
{{- range $k, $v := .Values.extraLabels }}
{{ $k }}: {{ $v }}
{{- end }}
{{- end -}}

{{/* Sélecteur minimal stable : name + instance uniquement (le selector est immuable). */}}
{{- define "notif.selectorLabels" -}}
app.kubernetes.io/name: {{ include "notif.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
