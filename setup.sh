#!/bin/bash

######################################################################
# RHOAI Demo - Pre-Demo Setup Script
# Run this BEFORE the demo to prepare the cluster.
#
# This script handles GPU infrastructure and operator setup.
# RHOAI itself is installed LIVE during the demo.
#
# Requires: ../ocp-gpu-setup repo to be present alongside this repo.
#
# IDEMPOTENT: Safe to re-run. Each step checks if work is already done
# and skips accordingly. oc apply is inherently idempotent.
######################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GPU_SETUP_DIR="${SCRIPT_DIR}/../ocp-gpu-setup"

# Helper: find a driver pod name (returns empty string if none found)
find_driver_pod() {
  oc get pods -n nvidia-gpu-operator --no-headers 2>/dev/null \
    | grep driver 2>/dev/null \
    | awk '{print $1}' \
    | head -n 1 \
    || true
}

echo "=============================================="
echo "RHOAI Demo - Pre-Demo Cluster Setup"
echo "=============================================="
echo ""
echo "This script will:"
echo "  1. Create GPU machinesets (interactive)"
echo "  2. Install Node Feature Discovery (NFD) operator"
echo "  3. Install NVIDIA GPU Operator v25.3.0"
echo "  4. Apply custom resources (ClusterPolicy, NFD config, driver)"
echo "  5. Verify GPU infrastructure"
echo "  6. Create OpenShift user for RHOAI Dashboard (htpasswd)"
echo "  7. Deploy MinIO (S3-compatible object storage)"
echo "  8. Deploy MySQL (Model Registry database backend)"
echo ""
echo "RHOAI operator will be installed LIVE during the demo."
echo ""
echo "This script is idempotent -- safe to re-run if interrupted."
echo ""

# Verify oc login
if ! oc whoami &>/dev/null; then
  echo "ERROR: Not logged into an OpenShift cluster."
  echo "  Run: oc login <cluster-url>"
  exit 1
fi

echo "Logged in as: $(oc whoami)"
echo "Cluster:      $(oc whoami --show-server)"
echo ""

# Verify ocp-gpu-setup repo is present
if [ ! -d "${GPU_SETUP_DIR}" ]; then
  echo "ERROR: ocp-gpu-setup repo not found at ${GPU_SETUP_DIR}"
  echo "  Expected it alongside this repo at: ../ocp-gpu-setup"
  echo "  Clone it:  git clone https://github.com/rh-aiservices-bu/ocp-gpu-setup.git ${GPU_SETUP_DIR}"
  exit 1
fi

echo "Found ocp-gpu-setup at: ${GPU_SETUP_DIR}"
echo ""

read -p "Press ENTER to begin setup, or Ctrl+C to cancel..."
echo ""

######################################################################
# Step 1: GPU Machinesets
######################################################################

echo "=============================================="
echo "Step 1: GPU Machineset Provisioning"
echo "=============================================="
echo ""
echo "This will launch an interactive script to create GPU worker nodes."
echo ""
echo "Recommended selections:"
echo "  - GPU type:    3) A10G Single GPU (24GB VRAM - matches Granite 3.3 2B model requirements)"
echo "  - Access mode: p (private)"
echo "  - Region:      your AWS region (e.g., us-east-2)"
echo "  - AZ:          1"
echo "  - Spot:        n (use on-demand for stability)"
echo "  - Disk size:   120 (default is fine for 2B models)"
echo ""

if oc get machineset -n openshift-machine-api 2>/dev/null | grep -qi gpu; then
  echo "GPU machineset may already exist:"
  oc get machineset -n openshift-machine-api | grep -i gpu || true
  echo ""
  read -p "Skip machineset creation? (y/n): " SKIP_MS
  if [ "$SKIP_MS" = "y" ]; then
    echo "Skipping machineset creation."
  else
    "${GPU_SETUP_DIR}/machine-set/gpu-machineset.sh"
  fi
else
  "${GPU_SETUP_DIR}/machine-set/gpu-machineset.sh"
fi

echo ""
echo "----------------------------------------------"
echo "Scale GPU MachineSet"
echo "----------------------------------------------"
echo ""
echo "The machineset was created with 1 replica. You may want to scale to 2."
echo ""
echo "  1 replica = 1 GPU node (fine if you run training and serving sequentially)"
echo "  2 replicas = 2 GPU nodes (needed to run a workbench AND inference service"
echo "               at the same time -- recommended for a smooth demo)"
echo ""
echo "You can also skip this and scale later with:"
echo "  oc scale machineset <name> -n openshift-machine-api --replicas=2"
echo ""

GPU_MS_NAME=$(oc get machineset -n openshift-machine-api -o name 2>/dev/null | grep gpu | head -1) || true
if [ -n "$GPU_MS_NAME" ]; then
  echo "Found GPU machineset: $GPU_MS_NAME"
  echo ""
  echo "  1) Scale to 1 replica"
  echo "  2) Scale to 2 replicas (recommended for demo)"
  echo "  3) Skip -- I'll scale it later"
  echo ""
  read -p "Select [1/2/3]: " SCALE_CHOICE
  case "$SCALE_CHOICE" in
    1)
      oc scale "$GPU_MS_NAME" -n openshift-machine-api --replicas=1
      echo "Scaled to 1 replica."
      ;;
    2)
      oc scale "$GPU_MS_NAME" -n openshift-machine-api --replicas=2
      echo "Scaled to 2 replicas."
      ;;
    3)
      echo "Skipping scaling."
      ;;
    *)
      echo "Invalid choice. Skipping scaling -- do it manually later."
      ;;
  esac
else
  echo "No GPU machineset found. You may need to create one first."
fi

echo ""
echo "Waiting for GPU nodes to become Ready..."
echo ""
echo "WHAT TO LOOK FOR:"
echo "  - MachineSet DESIRED/CURRENT/READY columns should all match"
echo "  - New nodes should appear in 'oc get nodes' with STATUS: Ready"
echo "  - New nodes will have names starting with 'ip-' (AWS EC2 instances)"
echo "  - This typically takes 5-10 minutes for EC2 instances to provision"
echo ""

while true; do
  echo ""
  echo "  1) Check status (oc get machineset, oc get nodes)"
  echo "  2) Continue to next step"
  echo ""
  read -p "Select [1/2]: " MS_CHOICE
  case "$MS_CHOICE" in
    1)
      echo ""
      echo "--- MachineSets ---"
      oc get machineset -n openshift-machine-api
      echo ""
      echo "--- Nodes ---"
      oc get nodes
      ;;
    2)
      break
      ;;
    *)
      echo "Invalid choice. Enter 1 or 2."
      ;;
  esac
done
echo ""

######################################################################
# Step 2: Node Feature Discovery
######################################################################

echo "=============================================="
echo "Step 2: Node Feature Discovery (NFD v4.20.0)"
echo "=============================================="
echo ""

if oc get csv -n openshift-nfd 2>/dev/null | grep -q nfd; then
  echo "NFD Operator already installed. Skipping."
else
  echo "Installing NFD operator..."
  oc apply -f "${GPU_SETUP_DIR}/nfd/"
  echo ""
  echo "Waiting for NFD operator to install..."
  echo ""
  echo "WHAT TO LOOK FOR:"
  echo "  - CSV PHASE column should show 'Succeeded' (not 'Installing' or 'Pending')"
  echo "  - You should see nfd-controller-manager and nfd-worker pods"
  echo "  - nfd-worker runs as a DaemonSet -- one pod per node"
  echo ""

  while true; do
    echo ""
    echo "  1) Check status (oc get csv -n openshift-nfd, oc get pods -n openshift-nfd)"
    echo "  2) Continue to next step"
    echo ""
    read -p "Select [1/2]: " NFD_CHOICE
    case "$NFD_CHOICE" in
      1)
        echo ""
        echo "--- NFD CSV Status ---"
        oc get csv -n openshift-nfd 2>/dev/null || echo "  No CSV found yet (operator still installing)."
        echo ""
        echo "--- NFD Pods ---"
        oc get pods -n openshift-nfd 2>/dev/null || echo "  No pods yet."
        ;;
      2)
        break
        ;;
      *)
        echo "Invalid choice. Enter 1 or 2."
        ;;
    esac
  done
fi
echo ""

######################################################################
# Step 3: NVIDIA GPU Operator
######################################################################

echo "=============================================="
echo "Step 3: NVIDIA GPU Operator (v25.3.0)"
echo "=============================================="
echo ""

if oc get csv -n nvidia-gpu-operator 2>/dev/null | grep -q gpu-operator; then
  echo "NVIDIA GPU Operator already installed. Skipping."
else
  echo "Installing NVIDIA GPU Operator..."
  oc apply -f "${GPU_SETUP_DIR}/gpu-operator/"
  echo ""
  echo "Waiting for GPU Operator to install..."
  echo ""
  echo "WHAT TO LOOK FOR:"
  echo "  - CSV PHASE should show 'Succeeded'"
  echo "  - gpu-operator-* pod should be Running"
  echo "  - This just installs the operator -- actual GPU pods come in Step 4"
  echo ""

  while true; do
    echo ""
    echo "  1) Check status (oc get csv -n nvidia-gpu-operator, oc get pods -n nvidia-gpu-operator)"
    echo "  2) Continue to next step"
    echo ""
    read -p "Select [1/2]: " GPU_CHOICE
    case "$GPU_CHOICE" in
      1)
        echo ""
        echo "--- GPU Operator CSV Status ---"
        oc get csv -n nvidia-gpu-operator 2>/dev/null || echo "  No CSV found yet (operator still installing)."
        echo ""
        echo "--- GPU Operator Pods ---"
        oc get pods -n nvidia-gpu-operator 2>/dev/null || echo "  No pods yet."
        ;;
      2)
        break
        ;;
      *)
        echo "Invalid choice. Enter 1 or 2."
        ;;
    esac
  done
fi
echo ""

######################################################################
# Step 4: Custom Resources
######################################################################

echo "=============================================="
echo "Step 4: Apply Custom Resources"
echo "=============================================="
echo ""
echo "Applying: ClusterPolicy, NodeFeatureDiscovery config, NVIDIADriver spec"
echo ""

oc apply -f "${GPU_SETUP_DIR}/crs/"

# The ocp-gpu-setup ClusterPolicy has driver.enabled=true, but it also deploys
# a separate NVIDIADriver CR (driver.yaml) that manages drivers independently.
# Both create driver pods targeting the same nodes, causing anti-affinity conflicts.
# Disable the ClusterPolicy driver to let the NVIDIADriver CR handle it.
# (See: https://github.com/rh-aiservices-bu/ocp-gpu-setup -- pending PR fix)
oc patch clusterpolicy gpu-cluster-policy --type merge -p '{"spec":{"driver":{"enabled":false}}}' 2>/dev/null || true

echo ""
echo "CRs applied. NVIDIA drivers will now compile on GPU nodes."
echo ""
echo "WHAT TO LOOK FOR:"
echo "  - nvidia-driver-daemonset-* pods: will start as Init, then Running"
echo "    (driver compilation takes 5-15 minutes)"
echo "  - nvidia-container-toolkit-daemonset-* pods: should be Running"
echo "  - nvidia-device-plugin-daemonset-* pods: should be Running"
echo "  - gpu-feature-discovery-* pods: should be Running"
echo "  - Once drivers are compiled, nvidia-smi should show the A10G GPU"
echo ""

while true; do
  echo ""
  echo "  1) Check status (oc get pods -n nvidia-gpu-operator, nvidia-smi)"
  echo "  2) Continue to verification"
  echo ""
  read -p "Select [1/2]: " CR_CHOICE
  case "$CR_CHOICE" in
    1)
      echo ""
      echo "--- GPU Operator Pods ---"
      oc get pods -n nvidia-gpu-operator 2>/dev/null || echo "  No pods yet."
      echo ""
      echo "--- nvidia-smi ---"
      DRIVER_POD=$(find_driver_pod)
      if [ -n "$DRIVER_POD" ]; then
        oc exec -n nvidia-gpu-operator "$DRIVER_POD" -c nvidia-driver-ctr -- nvidia-smi 2>/dev/null || echo "  nvidia-smi not yet available (drivers still compiling)."
      else
        echo "  No driver pod found yet."
      fi
      ;;
    2)
      break
      ;;
    *)
      echo "Invalid choice. Enter 1 or 2."
      ;;
  esac
done
echo ""

######################################################################
# Step 5: Verification
######################################################################

echo "=============================================="
echo "Step 5: Verification"
echo "=============================================="
echo ""

echo "--- Operators ---"
oc get csv -A 2>/dev/null | grep -E 'nvidia|nfd' || echo "  Some operators not yet installed."
echo ""

echo "--- GPU Nodes ---"
oc get nodes -l nvidia.com/gpu.present=true 2>/dev/null || echo "  No GPU nodes detected yet (NFD may still be scanning)."
echo ""

echo "--- GPU Operator Pods ---"
oc get pods -n nvidia-gpu-operator 2>/dev/null || echo "  No GPU operator pods found."
echo ""

echo "--- nvidia-smi ---"
DRIVER_POD=$(find_driver_pod)
if [ -n "$DRIVER_POD" ]; then
  oc exec -n nvidia-gpu-operator "$DRIVER_POD" -c nvidia-driver-ctr -- nvidia-smi 2>/dev/null || echo "  nvidia-smi not yet available (drivers may still be compiling)."
else
  echo "  No driver pod found yet."
fi

######################################################################
# Step 6: Create OpenShift User for RHOAI Dashboard
######################################################################

echo "=============================================="
echo "Step 6: Create OpenShift User for RHOAI Dashboard"
echo "=============================================="
echo ""
echo "The RHOAI Dashboard requires a real OpenShift user -- kubeadmin"
echo "is a bootstrap identity that can't resolve group memberships."
echo "Features like ServingRuntimes, Hardware Profiles, and admin"
echo "settings won't appear when logged in as kubeadmin."
echo ""
echo "This step will:"
echo "  1. Create an htpasswd identity provider"
echo "  2. Create a demo user with cluster-admin"
echo "  3. Add the user to the 'rhods-admins' group"
echo ""

# Check if htpasswd IDP already exists
if oc get oauth cluster -o json 2>/dev/null | grep -q htpasswd; then
  echo "htpasswd identity provider already configured. Skipping."
else
  read -p "Enter username for RHOAI admin (default: demo-admin): " RHOAI_USER
  RHOAI_USER=${RHOAI_USER:-demo-admin}

  while true; do
    read -s -p "Enter password for ${RHOAI_USER}: " RHOAI_PASS
    echo ""
    if [ -z "$RHOAI_PASS" ]; then
      echo "Password cannot be empty."
    else
      break
    fi
  done

  echo ""
  echo "Creating htpasswd secret..."

  # Generate htpasswd file
  HTPASSWD_FILE=$(mktemp)
  htpasswd -cbB "$HTPASSWD_FILE" "$RHOAI_USER" "$RHOAI_PASS"

  # Create secret
  oc create secret generic htpasswd-secret \
    --from-file=htpasswd="$HTPASSWD_FILE" \
    -n openshift-config \
    --dry-run=client -o yaml | oc apply -f -

  rm -f "$HTPASSWD_FILE"

  echo "Configuring OAuth with htpasswd identity provider..."

  oc patch oauth cluster --type merge -p '{
    "spec": {
      "identityProviders": [
        {
          "name": "htpasswd",
          "type": "HTPasswd",
          "mappingMethod": "claim",
          "htpasswd": {
            "fileData": {
              "name": "htpasswd-secret"
            }
          }
        }
      ]
    }
  }'

  echo ""
  echo "Granting cluster-admin to ${RHOAI_USER}..."
  oc adm policy add-cluster-role-to-user cluster-admin "$RHOAI_USER"

  echo ""
  echo "Adding ${RHOAI_USER} to rhods-admins group..."
  oc adm groups new rhods-admins 2>/dev/null || true
  oc adm groups add-users rhods-admins "$RHOAI_USER"

  echo ""
  echo "WHAT TO LOOK FOR:"
  echo "  - OAuth pods in openshift-authentication will restart (this takes ~1 min)"
  echo "  - Once restarted, you can log in via the OpenShift console with:"
  echo "      Username: ${RHOAI_USER}"
  echo "      Password: (the password you just entered)"
  echo "  - The RHOAI Dashboard will show ServingRuntimes, Hardware Profiles,"
  echo "    and admin settings when logged in as this user"
  echo ""

  while true; do
    echo ""
    echo "  1) Check status (oc get pods -n openshift-authentication)"
    echo "  2) Continue to next step"
    echo ""
    read -p "Select [1/2]: " AUTH_CHOICE
    case "$AUTH_CHOICE" in
      1)
        echo ""
        echo "--- Authentication Pods ---"
        oc get pods -n openshift-authentication 2>/dev/null || echo "  No pods found."
        echo ""
        echo "All pods should show Running and READY 1/1."
        echo "If you see Terminating + new pods, OAuth is still restarting."
        ;;
      2)
        break
        ;;
      *)
        echo "Invalid choice. Enter 1 or 2."
        ;;
    esac
  done
fi
echo ""

######################################################################
# Step 7: Deploy MinIO (S3 Object Storage)
######################################################################

echo "=============================================="
echo "Step 7: Deploy MinIO (S3-compatible Object Storage)"
echo "=============================================="
echo ""
echo "RHOAI requires S3-compatible storage for:"
echo "  - Model artifacts (trained model files)"
echo "  - Pipeline artifacts (logs, intermediate data)"
echo "  - Data connections in workbenches"
echo ""
echo "MinIO provides an S3-compatible API. In production you'd"
echo "use AWS S3, Ceph, or OpenShift Data Foundation instead."
echo ""

if oc get deployment minio 2>/dev/null | grep -q minio; then
  echo "MinIO already deployed. Skipping."
else
  oc apply -f "${SCRIPT_DIR}/manifests/minio.yaml"
  echo ""
  echo "Waiting for MinIO to be ready..."
  echo ""
  echo "WHAT TO LOOK FOR:"
  echo "  - minio pod STATUS: Running, READY: 1/1"
  echo ""
  oc rollout status deployment/minio 2>/dev/null || true
fi

echo ""
echo "MinIO UI route:"
oc get route minio-ui -o jsonpath='{.spec.host}' 2>/dev/null && echo "" || echo "  Route not yet available."
echo ""
echo ">>> DO NOT create the 'models' bucket yet."
echo ">>> During the demo, you'll open the MinIO UI live to show the audience"
echo ">>> where model artifacts are stored, then create the bucket on screen."
echo ">>> Login: minio / minio123"
echo ""

######################################################################
# Step 8: Deploy MySQL for Model Registry
######################################################################

echo "=============================================="
echo "Step 8: Deploy MySQL (Model Registry Backend)"
echo "=============================================="
echo ""
echo "The RHOAI Model Registry stores model metadata:"
echo "  - Model name, version, description"
echo "  - Artifact locations (S3 paths)"
echo "  - Deployment tracking"
echo ""
echo "It needs a database backend -- NOT for storing models"
echo "themselves, just the metadata about them."
echo ""

if oc get deployment model-registry-db -n rhoai-model-registry 2>/dev/null | grep -q model-registry; then
  echo "Model Registry DB already deployed. Skipping."
else
  oc apply -f "${SCRIPT_DIR}/manifests/model-registry-db.yaml"
  echo ""
  echo "Waiting for MySQL to be ready..."
  echo ""
  echo "WHAT TO LOOK FOR:"
  echo "  - model-registry-db pod STATUS: Running, READY: 1/1"
  echo "  - If stuck in CrashLoopBackOff, check logs: oc logs -n rhoai-model-registry deploy/model-registry-db"
  echo ""
  oc rollout status deployment/model-registry-db -n rhoai-model-registry 2>/dev/null || true
fi
echo ""

######################################################################
# Step 9: Final Verification
######################################################################

echo "=============================================="
echo "Step 9: Final Verification"
echo "=============================================="
echo ""

echo "--- Operators ---"
oc get csv -A 2>/dev/null | grep -E 'nvidia|nfd' || echo "  Some operators not yet installed."
echo ""

echo "--- GPU Nodes ---"
oc get nodes -l nvidia.com/gpu.present=true 2>/dev/null || echo "  No GPU nodes detected yet (NFD may still be scanning)."
echo ""

echo "--- MinIO ---"
oc get pods -l app=minio 2>/dev/null || echo "  MinIO not running."
echo ""

echo "--- Model Registry DB ---"
oc get pods -n rhoai-model-registry 2>/dev/null || echo "  Model Registry DB not running."
echo ""

echo "=============================================="
echo "Pre-demo setup complete!"
echo ""
echo "NEXT STEPS:"
echo "  1. DO NOT create the MinIO bucket -- that happens live during the demo"
echo "  2. RHOAI will be installed LIVE during the demo"
echo "  3. When ready, run: ./demo.sh"
echo "=============================================="
