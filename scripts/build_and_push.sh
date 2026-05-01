#!/usr/bin/env bash
# build_and_push.sh — Build les images Docker et les pousse sur ECR
# Usage : ./scripts/build_and_push.sh [TAG]
# TAG par défaut : latest (premier déploiement); utiliser un SHA/version pour les updates

set -euo pipefail

TAG="${1:-latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$ROOT_DIR/terraform"

echo "=== MLSecOps — Build & Push ECR ==="
echo "Tag : $TAG"
echo ""

# ── Récupérer la région et le compte AWS ──────────────────────────────────────
AWS_REGION=$(aws configure get region 2>/dev/null || echo "eu-west-3")
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo "Compte AWS : $AWS_ACCOUNT | Région : $AWS_REGION"

# ── Récupérer les URLs ECR depuis les outputs Terraform ───────────────────────
echo ""
echo "==> Lecture des outputs Terraform..."
cd "$TERRAFORM_DIR"
ECR_GO_PROXY=$(terraform output -raw ecr_go_proxy_url)
ECR_FASTAPI=$(terraform output -raw ecr_fastapi_url)
echo "ECR go-proxy : $ECR_GO_PROXY"
echo "ECR fastapi  : $ECR_FASTAPI"

# ── Login ECR ─────────────────────────────────────────────────────────────────
echo ""
echo "==> Login ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# ── Build & Push go-proxy ─────────────────────────────────────────────────────
echo ""
echo "==> Build go-proxy..."
docker build -t "mlsecops-go-proxy:$TAG" "$ROOT_DIR/go-proxy"
docker tag "mlsecops-go-proxy:$TAG" "$ECR_GO_PROXY:$TAG"
echo "==> Push go-proxy → ECR..."
docker push "$ECR_GO_PROXY:$TAG"

# ── Build & Push fastapi ──────────────────────────────────────────────────────
echo ""
echo "==> Build fastapi-middleware..."
docker build -t "mlsecops-fastapi:$TAG" "$ROOT_DIR/fastapi-middleware"
docker tag "mlsecops-fastapi:$TAG" "$ECR_FASTAPI:$TAG"
echo "==> Push fastapi → ECR..."
docker push "$ECR_FASTAPI:$TAG"

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo "=== Push terminé avec succès ==="
echo "  go-proxy : $ECR_GO_PROXY:$TAG"
echo "  fastapi  : $ECR_FASTAPI:$TAG"
echo ""
echo "Prochaines étapes :"
echo "  1. Vérifier les images dans ECR (console AWS ou aws ecr list-images)"
echo "  2. Forcer un redéploiement ECS :"
echo "     aws ecs update-service --cluster mlsecops-cluster --service mlsecops-service --force-new-deployment --region $AWS_REGION"
