#!/usr/bin/env bash
set -euo pipefail

#Variaveis
REGION="us-east-1"
CLUSTER_NAME="togglemaster-eks"
ARGO_NAMESPACE="argocd"
PORT_FORWARD_LOCAL_PORT=8080
ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
EXAMPLE_APP_FILE="exemplo-application.yaml"

#Log
log() { printf "\n[INFO] %s\n" "$1"; }

log "Atualizando kubeconfig para o cluster ${CLUSTER_NAME}"
aws eks --region "${REGION}" update-kubeconfig --name "${CLUSTER_NAME}"

log "Criando namespace ${ARGO_NAMESPACE} se não existir"
kubectl get ns "${ARGO_NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${ARGO_NAMESPACE}"

log "Aplicando manifest oficial do ArgoCD"
kubectl apply -n "${ARGO_NAMESPACE}" -f "${ARGOCD_INSTALL_URL}"

log "Aguardando deployments do ArgoCD ficarem disponíveis (timeout 10m)"

#Aguarda todos os deployments no namespace ArgoCD ficarem disponíveis
kubectl -n "${ARGO_NAMESPACE}" wait --for=condition=available deployment --all --timeout=600s

log "Listando pods no namespace ${ARGO_NAMESPACE}"
kubectl get pods -n "${ARGO_NAMESPACE}"

log "Recuperando senha inicial do admin"
if kubectl -n "${ARGO_NAMESPACE}" get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  ADMIN_PASSWORD=$(kubectl -n "${ARGO_NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode)
  printf "\nArgoCD admin user: %s\nArgoCD admin password: %s\n\n" "admin" "${ADMIN_PASSWORD}"
else
  log "Secret argocd-initial-admin-secret não encontrado. Verifique os pods do ArgoCD."
fi

log "Iniciando port-forward do serviço argocd-server em background na porta ${PORT_FORWARD_LOCAL_PORT}"

#Encerra port-forward anterior se existir
PF_PID_FILE="/tmp/argocd-portforward.pid"
if [ -f "${PF_PID_FILE}" ]; then
  OLD_PID=$(cat "${PF_PID_FILE}")
  if ps -p "${OLD_PID}" >/dev/null 2>&1; then
    log "Matando port-forward anterior PID ${OLD_PID}"
    kill "${OLD_PID}" || true
  fi
  rm -f "${PF_PID_FILE}"
fi

#Inicia port-forward em background com nohup
nohup kubectl port-forward svc/argocd-server -n "${ARGO_NAMESPACE}" "${PORT_FORWARD_LOCAL_PORT}":443 >/dev/null 2>&1 &
PF_PID=$!
echo "${PF_PID}" > "${PF_PID_FILE}"
log "Port-forward iniciado em background (PID ${PF_PID}). Acesse https://localhost:${PORT_FORWARD_LOCAL_PORT}"

log "Gerando Application de exemplo em ${EXAMPLE_APP_FILE}"
cat > "${EXAMPLE_APP_FILE}" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: exemplo-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/SEU_USUARIO/SEU_REPO.git' # <-- edite para seu repo
    targetRevision: HEAD
    path: k8s
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

log "Arquivo de exemplo criado. Edite 'repoURL' e 'path' no ${EXAMPLE_APP_FILE} antes de aplicar."
log "Para aplicar o Application de exemplo rode: kubectl apply -f ${EXAMPLE_APP_FILE}"

log "Validação rápida"
kubectl get pods -n "${ARGO_NAMESPACE}"
kubectl get svc -n "${ARGO_NAMESPACE}" | grep argocd-server || true

log "Concluído. Lembre-se de trocar a senha admin após o primeiro login."

