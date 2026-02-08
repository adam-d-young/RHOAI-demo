#!/bin/bash

######################################################################
# RHOAI Demo Script
# Uses demo-magic for stepped command execution with commentary.
# Press ENTER to advance each step. Ctrl+C to exit.
#
# Prerequisites (run setup.sh first):
#   - oc CLI logged into target cluster
#   - NFD Operator installed
#   - NVIDIA GPU Operator installed with ClusterPolicy
#   - GPU machineset provisioned (A10G x2)
#   - MinIO deployed (S3 storage)
#   - MySQL deployed (Model Registry backend)
######################################################################

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source demo-magic
. "${DEMO_DIR}/demo-magic.sh" -n

# Configure
DEMO_PROMPT="${GREEN}➜ ${CYAN}\W ${COLOR_RESET}"
TYPE_SPEED=20

# Detect browser-open command (macOS vs Linux)
if command -v open &>/dev/null; then
  BROWSER_OPEN="open"
elif command -v xdg-open &>/dev/null; then
  BROWSER_OPEN="xdg-open"
else
  BROWSER_OPEN="echo"   # fallback: just print the URL
fi

clear

echo ""
echo -e "${GREEN}   ___                   ___  _     _  __ _       _    ___ ${COLOR_RESET}"
echo -e "${GREEN}  / _ \ _ __  ___ _ _  / __|| |_  (_)/ _| |_   / \\  |_ _|${COLOR_RESET}"
echo -e "${GREEN} | (_) | '_ \/ -_) ' \ \__ \| ' \ | |  _|  _| | - |  | | ${COLOR_RESET}"
echo -e "${GREEN}  \___/| .__/\___|_||_||___/|_||_||_|_|  \__| |_|_| |___|${COLOR_RESET}"
echo -e "${GREEN}       |_|${COLOR_RESET}          ${CYAN}Get Started with OpenShift AI${COLOR_RESET}"
echo ""
echo -e "  ${CYAN}FSI Bootcamp Demo  •  GPU-Accelerated ML on OpenShift${COLOR_RESET}"
echo ""

wait

######################################################################
# SECTION 1: Check Current State
######################################################################

echo ""
echo -e "# 🔍 ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo -e "# ${GREEN}SECTION 1: Check Current State${COLOR_RESET}"
echo -e "# ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo "#"
echo "# 📋 What's already on this cluster (from setup):"
echo "#   • NFD Operator -- discovers hardware features"
echo "#   • NVIDIA GPU Operator -- manages the GPU stack"

wait

pe "oc get csv -A | grep -E 'nvidia|nfd|rhods'"

echo ""
echo "# 🖥️  GPU nodes online?"

wait

pe "oc get nodes -l nvidia.com/gpu.present=true"

echo ""
echo "# 🚫 These GPU nodes are tainted: nvidia.com/gpu=NoSchedule"
echo "#   • Set by the MachineSet -- nodes come up pre-tainted"
echo "#   • GPU Operator pods tolerate it (they have to run there)"
echo "#   • Everything else is blocked → protects expensive GPU nodes"
echo "#   • We'll need a HardwareProfile later to let ML workloads in"

wait

######################################################################
# SECTION 2: Verify NFD Operator
######################################################################

echo ""
echo -e "# 🔎 ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo -e "# ${GREEN}SECTION 2: Node Feature Discovery (NFD)${COLOR_RESET}"
echo -e "# ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo "#"
echo "# 👁️  NFD = the eyes of the cluster"
echo "#   • DaemonSet on every node -- scans for hardware"
echo "#   • GPUs, FPGAs, SR-IOV -- auto-labeled on the node"
echo "#   • GPU Operator reads these labels to deploy drivers"

wait

pe "oc get nodefeaturediscovery -n openshift-nfd"

echo ""
echo "# 🏷️  What did NFD find on our GPU nodes?"
echo "#   NFD labels use prefix: feature.node.kubernetes.io/"
echo "#   Key ones:"
echo "#     • pci-10de.present=true  → 10de = NVIDIA's PCI vendor ID"
echo "#     • kernel.version         → running kernel"
echo "#     • system-os_release.ID   → RHCOS / RHEL"

wait

pe "oc get nodes -l nvidia.com/gpu.present=true -o json | jq '.items[0].metadata.labels | with_entries(select(.key | (startswith(\"feature.node.kubernetes.io\") and test(\"pci|kernel|os_release|cpu-model\"))))'"

wait

######################################################################
# SECTION 3: Verify NVIDIA GPU Operator
######################################################################

echo ""
echo -e "# 🎮 ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo -e "# ${GREEN}SECTION 3: NVIDIA GPU Operator${COLOR_RESET}"
echo -e "# ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo "#"
echo "# 🔧 One operator, entire GPU stack:"
echo "#   • Drivers, device plugins, container toolkit, monitoring"
echo "#   • All driven by a single CR: ClusterPolicy"

wait

pe "oc get clusterpolicy"

echo ""
echo "# 📋 What does the ClusterPolicy configure?"

wait

pe "less ${DEMO_DIR}/manifests/gpu-cluster-policy.yaml"

echo ""
echo ""
echo "# 🏷️  GPU Feature Discovery (GFD) adds nvidia.com/gpu.* labels"
echo "#   • Product name, VRAM, CUDA version, driver version"
echo "#   • Different from NFD -- GFD queries the GPU directly"

wait

pe "oc get nodes -l nvidia.com/gpu.present=true -o custom-columns='NODE:.metadata.name,GPU:.metadata.labels.nvidia\.com/gpu\.product,VRAM_MB:.metadata.labels.nvidia\.com/gpu\.memory,GPUs:.status.allocatable.nvidia\.com/gpu'"

echo ""
echo "# 🚀 Moment of truth -- nvidia-smi"
echo "#   • NVIDIA System Management Interface -- CLI to query the GPU"
echo "#   • We're running it FROM INSIDE a driver pod (not the host)"
echo "#   • If it returns output, the full stack is working:"
echo "#     drivers compiled → device plugin registered → toolkit configured"
echo "#"
echo "# 📖 How to read the output:"
echo "#   • GPU name + VRAM (A10G, 23028MiB ≈ 22.5GiB -- marketed as 24GB)"
echo "#   • Driver 570.x + CUDA 12.8"
echo "#   • Pwr: 24W/300W → idle draw / max cap (300W under full load)"
echo "#   • P8 = performance state (P0=max, P12=min) -- P8 means idle"
echo "#   • Temp 28C → cool, expect 60-80C under load"
echo "#   • GPU-Util 0%, no processes → nothing scheduled yet"

wait

pe "oc exec -n nvidia-gpu-operator \$(oc get pods -n nvidia-gpu-operator --no-headers | grep driver | awk '{print \$1}' | head -n 1) -c nvidia-driver-ctr -- nvidia-smi"

wait

######################################################################
# SECTION 4: Install RHOAI Operator
######################################################################

echo ""
echo -e "# 📦 ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo -e "# ${GREEN}SECTION 4: Install Red Hat OpenShift AI${COLOR_RESET}"
echo -e "# ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo "#"
echo "# 🧠 RHOAI = the ML platform layer on top of OpenShift"
echo "#   • Workbenches, model serving, pipelines, model registry"
echo "#   • Install the operator from OperatorHub in the console"

wait

pe "OCP_CONSOLE=\$(oc whoami --show-console) && echo \$OCP_CONSOLE"

pe "$BROWSER_OPEN \$OCP_CONSOLE"

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Install RHOAI in browser${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 OpenShift Console → Operators → OperatorHub"
echo "#   → Search: 'OpenShift AI'"
echo "#   → Click 'Red Hat OpenShift AI'"
echo "#   → Click 'Install'"
echo "#   → Channel: fast | Update approval: Automatic"
echo "#   → Accept all other defaults → Click 'Install'"
echo "#   → ⏳ Wait for CSV status: 'Succeeded'"
echo "#"
echo -e "# ${RED}   DO NOT press ENTER until the operator shows 'Succeeded'${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo "# 🔄 Verify the operator installed:"

wait

pe "oc get csv -A | grep rhods"

echo ""
echo "# 📋 The operator auto-creates a default DataScienceCluster"
echo "#   • RHOAI 3.x defaults enable everything we need:"
echo "#     Dashboard, Workbenches, ModelMeshServing, ModelRegistry"
echo "#   • No changes needed -- let's verify:"

wait

pe "oc get datasciencecluster"

pe "oc get datasciencecluster default-dsc -o jsonpath='{.spec.components}' | jq ."

echo ""
echo "# ✅ RHOAI is ready -- all components managed by the operator"

wait

######################################################################
# SECTION 5: Hardware Profile
######################################################################

echo ""
echo -e "# 🛡️  ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo -e "# ${GREEN}SECTION 5: Hardware Profile with GPU Toleration${COLOR_RESET}"
echo -e "# ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo "#"
echo "# 🔑 Remember the GPU taint from Section 1?"
echo "#   • HardwareProfile is how RHOAI workloads get past it"
echo "#   1. Requests nvidia.com/gpu: 1"
echo "#   2. Tolerates the taint → workbench pods CAN schedule"

wait

pe "less ${DEMO_DIR}/manifests/hardware-profile.yaml"

pe "oc apply -f ${DEMO_DIR}/manifests/hardware-profile.yaml"

wait

pe "RHOAI_URL=\$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='https://{.spec.host}') && echo \$RHOAI_URL"

pe "$BROWSER_OPEN \$RHOAI_URL"

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Verify HardwareProfile in browser${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 RHOAI Dashboard:"
echo "#   → Settings (left sidebar) → Hardware profiles"
echo "#   → 'nvidia-gpu' profile should appear"
echo "#   → Click it to verify:"
echo "#     • Resource: nvidia.com/gpu: 1"
echo "#     • Toleration: nvidia.com/gpu NoSchedule"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

######################################################################
# SECTION 6: Verify Pre-deployed Infrastructure
######################################################################

echo ""
echo -e "# 🏗️  ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo -e "# ${GREEN}SECTION 6: Pre-deployed Infrastructure${COLOR_RESET}"
echo -e "# ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo "#"
echo "# 🧱 Two backing services (deployed during setup):"
echo "#"
echo "#   📦 MinIO → S3-compatible object storage"
echo "#     • Model files, pipeline artifacts"
echo "#     • Production = AWS S3 / Ceph / ODF"
echo "#"
echo "#   🗄️  MySQL → Model Registry metadata"
echo "#     • Name, version, artifact paths"
echo "#     • NOT the models -- just the catalog"

wait

echo ""
echo "# 🔄 Verify they're running:"

wait

pe "oc get pods -l app=minio"

pe "oc get pods -n rhoai-model-registry"

echo ""
echo "# 🪣 Time to create our model storage bucket in MinIO!"
echo "#   → This is where trained models land before serving"

wait

pe "MINIO_URL=\$(oc get route minio-ui -o jsonpath='https://{.spec.host}') && echo \$MINIO_URL"

pe "$BROWSER_OPEN \$MINIO_URL"

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Create 'models' bucket in MinIO${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 MinIO Console:"
echo "#   → Login:  Username: minio  |  Password: minio123"
echo "#   → Sidebar → 'Object Browser'"
echo "#   → Click 'Create a Bucket'"
echo "#   → Bucket name: models"
echo "#   → Click 'Create Bucket'"
echo "#   → Leave it empty -- notebook will upload here later"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

######################################################################
# SECTION 7: Serving Runtime
######################################################################

echo ""
echo -e "# 🧠 ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo -e "# ${GREEN}SECTION 7: GPU Serving Runtime${COLOR_RESET}"
echo -e "# ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo "#"
echo "# 🖥️  ServingRuntime = how models get served on GPUs"
echo "#   • Using NVIDIA Triton Inference Server"
echo "#   • Supports TensorFlow, Keras, ONNX out of the box"

wait

pe "less ${DEMO_DIR}/manifests/serving-runtime.yaml"

pe "oc apply -f ${DEMO_DIR}/manifests/serving-runtime.yaml"

echo ""
echo "# ✅ 'Triton Inference Server (GPU)' now available in RHOAI Dashboard!"

wait

######################################################################
# SECTION 8: Workbench Demo (Manual Steps)
######################################################################

echo ""
echo -e "# 🧪 ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo -e "# ${GREEN}SECTION 8: Workbench & End-to-End ML Workflow${COLOR_RESET}"
echo -e "# ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo "#"
echo "# 🎯 The fun part! Full ML lifecycle:"
echo "#   1️⃣  Create Data Science Project"
echo "#   2️⃣  Connect S3 storage"
echo "#   3️⃣  Launch GPU workbench"
echo "#   4️⃣  Train + upload model"
echo "#   5️⃣  Deploy for inference"

wait

pe "RHOAI_URL=\$(oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='https://{.spec.host}') && echo \$RHOAI_URL"

pe "$BROWSER_OPEN \$RHOAI_URL"

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Create Data Science Project${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 1️⃣  🌐 RHOAI Dashboard:"
echo "#   → 'Data Science Projects' in left sidebar"
echo "#   → Click 'Create data science project'"
echo "#   → Name: fsi-demo"
echo "#   → Click 'Create'"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Add Data Connection${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 2️⃣  Inside fsi-demo project → 'Data connections' tab"
echo "#   → Click 'Add data connection'"
echo "#   → Name:       minio-models"
echo "#   → Access key:  minio"
echo "#   → Secret key:  minio123"
echo "#   → Endpoint:    http://minio-service:9000"
echo "#   → Bucket:      models"
echo "#   → Click 'Add data connection'"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Create GPU Workbench${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 3️⃣  'Workbenches' tab → 'Create workbench'"
echo "#   → Name: gpu-workbench"
echo "#   → Image: TensorFlow (select CUDA variant if available)"
echo "#   → Hardware profile: nvidia-gpu"
echo "#   → Environment variables → 'Add variable':"
echo "#     → Type: Config Map → Key/value"
echo "#     → Key:   LD_LIBRARY_PATH"
echo "#     → Value: /opt/app-root/src/driver-override"
echo "#   → Data connections → check 'Use existing data connection'"
echo "#     → Select: minio-models"
echo "#   → Click 'Create workbench'"
echo "#   → ⏳ Wait for status: Running"
echo "#   → Click 'Open' to launch JupyterLab"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Run notebooks in JupyterLab${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 4️⃣  Upload notebooks from this repo's notebooks/ folder"
echo "#   → Run in order:"
echo "#"
echo "#   📓 gpu-check.py        → Can TensorFlow see the A10G?"
echo "#   📓 gpu-demo.py         → GPU vs CPU matrix multiply"
echo "#   📓 train-and-upload.py → Train on GPU, upload to MinIO"
echo "#"
echo -e "# ${RED}   DO NOT continue until train-and-upload.py completes${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

pe "$BROWSER_OPEN \$MINIO_URL"

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Verify model in MinIO${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 5️⃣  🌐 MinIO Console:"
echo "#   → Object Browser → 'models' bucket"
echo "#   → Model artifact should be here"
echo "#   → Note the path (e.g. 'model/') -- needed for deploy step"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

pe "$BROWSER_OPEN \$RHOAI_URL"

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Deploy model for inference${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 6️⃣  🌐 RHOAI Dashboard → fsi-demo project"
echo "#   → 'Models' tab → Click 'Deploy model'"
echo "#   → Model name:      fsi-demo-model"
echo "#   → Serving runtime:  Triton Inference Server (GPU)"
echo "#   → Model framework:  tensorflow"
echo "#   → Model location:   Existing data connection → minio-models"
echo "#   → Path: (the path from MinIO, e.g. 'model/')"
echo "#   → Click 'Deploy'"
echo "#   → ⏳ Wait for status: ✅ green checkmark"
echo "#   → Copy the inference URL"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo -e "# 🎉 ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo "#"
echo -e "#   ${GREEN}Demo complete!${COLOR_RESET}"
echo "#"
echo -e "#   Bare metal GPUs → trained model → live inference"
echo -e "#   All on ${CYAN}OpenShift AI${COLOR_RESET} 🚀"
echo "#"
echo -e "# ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
