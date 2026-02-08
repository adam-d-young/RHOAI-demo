#!/bin/bash

######################################################################
# RHOAI Demo Teardown Script
#
# Two modes:
#   Default:    Undo demo.sh changes (projects, deployments, profiles)
#   Full reset: Also undo setup.sh changes (MinIO, MySQL, GPU, RHOAI)
#
# Usage:
#   ./teardown.sh          # Demo reset (default)
#   ./teardown.sh --full   # Full cluster reset (requires confirmation)
######################################################################

set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FULL_RESET=false

if [ "${1:-}" = "--full" ]; then
  FULL_RESET=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Preflight
if ! oc whoami &>/dev/null; then
  echo -e "${RED}ERROR: Not logged into OpenShift. Run: oc login <cluster-url>${NC}"
  exit 1
fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       RHOAI Demo Teardown                    ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

if [ "$FULL_RESET" = true ]; then
  echo -e "${RED}MODE: FULL CLUSTER RESET${NC}"
  echo ""
  echo "This will remove EVERYTHING created by setup.sh and demo.sh:"
  echo "  • All demo namespaces (granite-demo, fsi-demo)"
  echo "  • Model Registry instance + MySQL database"
  echo "  • Hardware profiles, serving runtimes"
  echo "  • RHOAI operator"
  echo "  • MinIO S3 storage (and all stored models)"
  echo "  • GPU operators (NFD, NVIDIA GPU Operator)"
  echo "  • GPU machineset (GPU nodes will be deprovisioned)"
  echo "  • Demo user (htpasswd)"
  echo ""
  echo -e "${RED}THIS IS DESTRUCTIVE AND CANNOT BE UNDONE.${NC}"
  echo ""
  read -p "Type 'FULL RESET' to confirm: " CONFIRM1
  if [ "$CONFIRM1" != "FULL RESET" ]; then
    echo "Aborted."
    exit 0
  fi
  echo ""
  read -p "Are you ABSOLUTELY sure? (yes/no): " CONFIRM2
  if [ "$CONFIRM2" != "yes" ]; then
    echo "Aborted."
    exit 0
  fi
else
  echo -e "${GREEN}MODE: Demo Reset (default)${NC}"
  echo ""
  echo "This will remove resources created during demo.sh:"
  echo "  • granite-demo namespace (Granite LLM, LlamaStack)"
  echo "  • fsi-demo namespace (workbench, pipelines, model deployments)"
  echo "  • Model Registry instance (rhoai-model-registries)"
  echo "  • Hardware profile (nvidia-gpu)"
  echo "  • Triton serving runtime template"
  echo "  • LlamaStack Helm releases"
  echo "  • MinIO data (models bucket, uploaded artifacts)"
  echo "  • MySQL data (model registry metadata)"
  echo ""
  echo "Infrastructure (MinIO, MySQL, GPU, RHOAI) will be preserved but"
  echo "storage data will be cleared so the demo starts fresh."
  echo ""
  read -p "Continue? (y/n): " CONFIRM
  if [ "$CONFIRM" != "y" ]; then
    echo "Aborted."
    exit 0
  fi
fi

echo ""

# Helper: delete resource if it exists, no error if missing
safe_delete() {
  local resource="$1"
  local name="$2"
  local namespace="${3:-}"
  local ns_flag=""
  if [ -n "$namespace" ]; then
    ns_flag="-n $namespace"
  fi

  if oc get "$resource" "$name" $ns_flag &>/dev/null; then
    echo -e "  ${YELLOW}Deleting ${resource}/${name}${namespace:+ in ${namespace}}...${NC}"
    oc delete "$resource" "$name" $ns_flag --wait=false 2>/dev/null || true
  else
    echo -e "  ${CYAN}${resource}/${name} not found (already removed)${NC}"
  fi
}

# Helper: delete namespace if it exists
safe_delete_namespace() {
  local ns="$1"
  if oc get namespace "$ns" &>/dev/null; then
    echo -e "  ${YELLOW}Deleting namespace ${ns}...${NC}"
    # Delete all InferenceServices first (they can block namespace deletion)
    oc delete inferenceservice --all -n "$ns" --wait=false 2>/dev/null || true
    # Delete all workbenches
    oc delete workbench --all -n "$ns" --wait=false 2>/dev/null || true
    # Delete DSPA
    oc delete dspa --all -n "$ns" --wait=false 2>/dev/null || true
    # Now delete the namespace
    oc delete namespace "$ns" --wait=false 2>/dev/null || true
  else
    echo -e "  ${CYAN}Namespace ${ns} not found (already removed)${NC}"
  fi
}

######################################################################
# DEMO RESET -- Resources created by demo.sh
######################################################################

echo "═══════════════════════════════════════════"
echo "Step 1: Remove LlamaStack Helm releases"
echo "═══════════════════════════════════════════"

if command -v helm &>/dev/null; then
  for release in llama-stack-playground llama-stack-instance; do
    if helm status "$release" -n granite-demo &>/dev/null; then
      echo -e "  ${YELLOW}Uninstalling Helm release: ${release}...${NC}"
      helm uninstall "$release" -n granite-demo 2>/dev/null || true
    else
      echo -e "  ${CYAN}Helm release ${release} not found${NC}"
    fi
  done
else
  echo -e "  ${CYAN}Helm not installed, skipping Helm cleanup${NC}"
fi
echo ""

echo "═══════════════════════════════════════════"
echo "Step 2: Delete demo namespaces"
echo "═══════════════════════════════════════════"

safe_delete_namespace "granite-demo"
safe_delete_namespace "fsi-demo"
echo ""

echo "═══════════════════════════════════════════"
echo "Step 3: Delete Model Registry instance"
echo "═══════════════════════════════════════════"

safe_delete "modelregistry" "fsi-model-registry" "rhoai-model-registries"
safe_delete "secret" "model-registry-db-credential" "rhoai-model-registries"
safe_delete_namespace "rhoai-model-registries"
echo ""

echo "═══════════════════════════════════════════"
echo "Step 4: Delete Hardware Profile"
echo "═══════════════════════════════════════════"

safe_delete "hardwareprofile" "nvidia-gpu" "redhat-ods-applications"
echo ""

echo "═══════════════════════════════════════════"
echo "Step 5: Delete Triton ServingRuntime template"
echo "═══════════════════════════════════════════"

safe_delete "template" "triton-kserve-gpu-template" "redhat-ods-applications"
echo ""

echo "═══════════════════════════════════════════"
echo "Step 6: Revert LlamaStack DSC patch"
echo "═══════════════════════════════════════════"

if oc get datasciencecluster default-dsc &>/dev/null; then
  echo -e "  ${YELLOW}Setting llamastackoperator back to Removed...${NC}"
  oc patch datasciencecluster default-dsc --type merge \
    -p '{"spec":{"components":{"llamastackoperator":{"managementState":"Removed"}}}}' 2>/dev/null || true
else
  echo -e "  ${CYAN}DataScienceCluster not found${NC}"
fi
echo ""

echo "═══════════════════════════════════════════"
echo "Step 7: Reset MinIO and MySQL data"
echo "═══════════════════════════════════════════"

echo -e "  ${YELLOW}Clearing MinIO data (models bucket, uploaded artifacts)...${NC}"
# Delete deployment + PVC, then re-apply manifest to recreate fresh
if oc get deployment minio &>/dev/null; then
  oc delete deployment minio --wait=false 2>/dev/null || true
fi
if oc get pvc minio-pvc &>/dev/null; then
  oc delete pvc minio-pvc --wait=true 2>/dev/null || true
fi
echo -e "  ${YELLOW}Re-applying MinIO manifest (fresh PVC)...${NC}"
oc apply -f "${DEMO_DIR}/manifests/minio.yaml"

echo ""
echo -e "  ${YELLOW}Clearing MySQL data (model registry metadata)...${NC}"
if oc get deployment model-registry-db -n rhoai-model-registry &>/dev/null; then
  oc delete deployment model-registry-db -n rhoai-model-registry --wait=false 2>/dev/null || true
fi
if oc get pvc model-registry-db-pvc -n rhoai-model-registry &>/dev/null; then
  oc delete pvc model-registry-db-pvc -n rhoai-model-registry --wait=true 2>/dev/null || true
fi
echo -e "  ${YELLOW}Re-applying MySQL manifest (fresh PVC)...${NC}"
oc apply -f "${DEMO_DIR}/manifests/model-registry-db.yaml"

echo ""
echo -e "  ${GREEN}Storage reset. MinIO and MySQL will start with empty data.${NC}"
echo ""

######################################################################
# FULL RESET -- Resources created by setup.sh
######################################################################

if [ "$FULL_RESET" = true ]; then

echo ""
echo -e "${RED}═══════════════════════════════════════════${NC}"
echo -e "${RED}FULL RESET: Removing setup.sh resources${NC}"
echo -e "${RED}═══════════════════════════════════════════${NC}"
echo ""

echo "═══════════════════════════════════════════"
echo "Step 7: Uninstall RHOAI operator"
echo "═══════════════════════════════════════════"

# Delete DSC first
safe_delete "datasciencecluster" "default-dsc"

# Wait for DSC to actually be gone
echo -e "  ${YELLOW}Waiting for DataScienceCluster to be fully removed...${NC}"
oc wait --for=delete datasciencecluster/default-dsc --timeout=120s 2>/dev/null || true

# Delete DSCI if present
DSCI_NAME=$(oc get dsci -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
if [ -n "$DSCI_NAME" ]; then
  safe_delete "dsci" "$DSCI_NAME"
fi

# Delete subscription
RHOAI_SUB=$(oc get subscription -n redhat-ods-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
if [ -n "$RHOAI_SUB" ]; then
  echo -e "  ${YELLOW}Deleting RHOAI Subscription...${NC}"
  oc delete subscription "$RHOAI_SUB" -n redhat-ods-operator 2>/dev/null || true
fi

# Delete CSV
RHOAI_CSV=$(oc get csv -n redhat-ods-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
if [ -n "$RHOAI_CSV" ]; then
  echo -e "  ${YELLOW}Deleting RHOAI CSV: ${RHOAI_CSV}...${NC}"
  oc delete csv "$RHOAI_CSV" -n redhat-ods-operator 2>/dev/null || true
fi
echo ""

echo "═══════════════════════════════════════════"
echo "Step 8: Delete MinIO"
echo "═══════════════════════════════════════════"

safe_delete "deployment" "minio" "default"
safe_delete "service" "minio-service" "default"
safe_delete "route" "minio-api" "default"
safe_delete "route" "minio-ui" "default"
safe_delete "secret" "minio-secret" "default"
safe_delete "pvc" "minio-pvc" "default"
echo ""

echo "═══════════════════════════════════════════"
echo "Step 9: Delete MySQL (Model Registry DB)"
echo "═══════════════════════════════════════════"

safe_delete_namespace "rhoai-model-registry"
echo ""

echo "═══════════════════════════════════════════"
echo "Step 10: Delete GPU operators"
echo "═══════════════════════════════════════════"

echo ""
echo -e "${RED}WARNING: This will remove GPU drivers from all nodes.${NC}"
read -p "Delete GPU Operator and NFD? (yes/no): " GPU_CONFIRM
if [ "$GPU_CONFIRM" = "yes" ]; then
  # Delete ClusterPolicy first
  safe_delete "clusterpolicy" "gpu-cluster-policy"

  echo -e "  ${YELLOW}Waiting for ClusterPolicy cleanup...${NC}"
  sleep 10

  # Delete GPU Operator subscription + CSV
  GPU_SUB=$(oc get subscription -n nvidia-gpu-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
  if [ -n "$GPU_SUB" ]; then
    oc delete subscription "$GPU_SUB" -n nvidia-gpu-operator 2>/dev/null || true
  fi
  GPU_CSV=$(oc get csv -n nvidia-gpu-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
  if [ -n "$GPU_CSV" ]; then
    oc delete csv "$GPU_CSV" -n nvidia-gpu-operator 2>/dev/null || true
  fi

  # Delete NFD
  NFD_DISC=$(oc get nodefeaturediscovery -n openshift-nfd -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
  if [ -n "$NFD_DISC" ]; then
    oc delete nodefeaturediscovery "$NFD_DISC" -n openshift-nfd 2>/dev/null || true
  fi
  NFD_SUB=$(oc get subscription -n openshift-nfd -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
  if [ -n "$NFD_SUB" ]; then
    oc delete subscription "$NFD_SUB" -n openshift-nfd 2>/dev/null || true
  fi
  NFD_CSV=$(oc get csv -n openshift-nfd -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
  if [ -n "$NFD_CSV" ]; then
    oc delete csv "$NFD_CSV" -n openshift-nfd 2>/dev/null || true
  fi

  echo -e "  ${GREEN}GPU operators removed${NC}"
else
  echo "  Skipping GPU operator removal."
fi
echo ""

echo "═══════════════════════════════════════════"
echo "Step 11: Delete GPU machineset"
echo "═══════════════════════════════════════════"

echo ""
GPU_MS=$(oc get machineset -n openshift-machine-api -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -i gpu || true)
if [ -n "$GPU_MS" ]; then
  echo "Found GPU machinesets:"
  echo "$GPU_MS" | while read ms; do echo "  • $ms"; done
  echo ""
  echo -e "${RED}WARNING: This will decommission GPU nodes. They may take 10+ minutes to drain.${NC}"
  read -p "Delete GPU machineset(s)? (yes/no): " MS_CONFIRM
  if [ "$MS_CONFIRM" = "yes" ]; then
    echo "$GPU_MS" | while read ms; do
      echo -e "  ${YELLOW}Deleting machineset: ${ms}...${NC}"
      oc delete machineset "$ms" -n openshift-machine-api 2>/dev/null || true
    done
  else
    echo "  Skipping machineset deletion."
  fi
else
  echo -e "  ${CYAN}No GPU machinesets found${NC}"
fi
echo ""

echo "═══════════════════════════════════════════"
echo "Step 12: Remove demo user"
echo "═══════════════════════════════════════════"

# Note: Removing htpasswd IDP from OAuth is complex (need to patch the array).
# Just note it for the user rather than risk breaking OAuth.
echo "  The htpasswd user and OAuth IDP configuration are left in place."
echo "  To remove manually:"
echo "    oc delete secret htpasswd-secret -n openshift-config"
echo "    oc edit oauth cluster  # Remove the htpasswd identity provider"
echo ""

echo ""
echo -e "${RED}═══════════════════════════════════════════${NC}"
echo -e "${RED}FULL RESET COMPLETE${NC}"
echo -e "${RED}═══════════════════════════════════════════${NC}"
echo ""
echo "Notes:"
echo "  • GPU nodes may take 10+ minutes to fully drain and terminate"
echo "  • RHOAI namespace cleanup may take a few minutes"
echo "  • Check: oc get namespaces | grep -E 'fsi|granite|rhoai|nvidia|nfd'"

else

echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}DEMO RESET COMPLETE${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "Cleaned up demo resources. Setup resources preserved:"
echo "  ✅ MinIO (S3 storage) -- restarted with empty data"
echo "  ✅ MySQL (Model Registry DB) -- restarted with empty data"
echo "  ✅ GPU operators -- still running"
echo "  ✅ RHOAI operator -- still installed"
echo ""
echo "Namespace cleanup may take a minute. Check with:"
echo "  oc get namespaces | grep -E 'fsi|granite|rhoai-model-registries'"
echo ""
echo "Ready to re-run: ./demo.sh"

fi
