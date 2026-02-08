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

# Preflight: check required tools
MISSING=""
for tool in oc bat helm; do
  if ! command -v "$tool" &>/dev/null; then
    MISSING="$MISSING $tool"
  fi
done
if ! oc whoami &>/dev/null; then
  MISSING="$MISSING oc(not-logged-in)"
fi
if [ -n "$MISSING" ]; then
  echo "ERROR: Missing required tools:$MISSING"
  echo ""
  echo "  oc   → brew install openshift-cli (or download from OpenShift console)"
  echo "  bat  → brew install bat"
  echo "  helm → brew install helm"
  echo "  oc login → oc login <cluster-url>"
  exit 1
fi

# Source demo-magic
. "${DEMO_DIR}/demo-magic.sh" -n

# Helper: verify a condition before continuing, retry on failure
# Usage: verify_step "description" "command that returns 0 on success"
verify_step() {
  local desc="$1"
  local cmd="$2"
  while true; do
    if eval "$cmd" &>/dev/null; then
      echo -e "  ${GREEN}✅ ${desc}${COLOR_RESET}"
      return 0
    else
      echo -e "  ${RED}❌ ${desc} -- not ready${COLOR_RESET}"
      echo ""
      read -p "  Press ENTER to retry, or 's' to skip: " choice
      if [ "$choice" = "s" ]; then
        echo -e "  ${CYAN}⏭️  Skipped${COLOR_RESET}"
        return 1
      fi
    fi
  done
}

# Helper: compare live resource against manifest, show diff if mismatched
# Usage: verify_manifest "description" "manifest-file"
verify_manifest() {
  local desc="$1"
  local manifest="$2"
  while true; do
    local diff_output
    diff_output=$(oc diff -f "${DEMO_DIR}/${manifest}" 2>&1)
    local rc=$?
    if [ $rc -eq 0 ]; then
      echo -e "  ${GREEN}✅ ${desc} -- matches manifest${COLOR_RESET}"
      return 0
    elif [ $rc -eq 1 ]; then
      echo -e "  ${CYAN}⚠️  ${desc} -- differs from manifest:${COLOR_RESET}"
      echo ""
      echo "$diff_output"
      echo ""
      read -p "  (a)pply manifest to fix / (c)ontinue anyway / (r)etry check: " choice
      case "$choice" in
        a) oc apply -f "${DEMO_DIR}/${manifest}" &>/dev/null
           echo -e "  ${GREEN}  Applied.${COLOR_RESET}"
           continue ;;
        c) return 0 ;;
        *) continue ;;
      esac
    else
      echo -e "  ${RED}❌ ${desc} -- not found or error${COLOR_RESET}"
      echo ""
      read -p "  Press ENTER to retry, or 's' to skip: " choice
      if [ "$choice" = "s" ]; then
        echo -e "  ${CYAN}⏭️  Skipped${COLOR_RESET}"
        return 1
      fi
    fi
  done
}

# Helper: section header with optional skip
# Returns 1 if skipped (use: begin_section ... || return 0)
begin_section() {
  local num="$1" icon="$2" title="$3"
  echo ""
  echo -e "# ${icon} ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
  echo -e "# ${GREEN}SECTION ${num}: ${title}${COLOR_RESET}"
  echo -e "# ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
  read -p "  Skip this section? (y/N): " SKIP_SECTION
  if [ "$SKIP_SECTION" = "y" ]; then
    echo -e "  ${CYAN}⏭️  Skipped Section ${num}${COLOR_RESET}"
    return 1
  fi
  return 0
}

# Helper: ensure a variable is set, try to resolve it if not
# Usage: ensure_var RHOAI_URL "oc get gateway ..."
ensure_var() {
  local varname="$1"
  local cmd="$2"
  if [ -z "${!varname:-}" ]; then
    local val
    val=$(eval "$cmd" 2>/dev/null) || true
    if [ -n "$val" ]; then
      eval "$varname=\"$val\""
      echo -e "  ${GREEN}✅ ${varname} resolved${COLOR_RESET}"
    else
      echo -e "  ${RED}⚠️  Could not resolve ${varname} -- was a previous section skipped?${COLOR_RESET}"
    fi
  fi
}

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
echo -e "${GREEN}  ___                 ___ _    _  __ _       _   ___ ${COLOR_RESET}"
echo -e "${GREEN} / _ \ _ __  ___ _ _ / __| |_ (_)/ _| |_    /_\ |_ _|${COLOR_RESET}"
echo -e "${GREEN}| (_) | '_ \/ -_) ' \\\\__ \ ' \| |_|  _|     / _ \ | | ${COLOR_RESET}"
echo -e "${GREEN} \___/| .__/\___|_||_|___/_||_|_|_|  \__| /_/ \_\___|${COLOR_RESET}"
echo -e "${GREEN}      |_|${COLOR_RESET}         ${CYAN}Get Started with OpenShift AI${COLOR_RESET}"
echo ""
echo -e "  ${CYAN}FSI Bootcamp Demo  •  GPU-Accelerated ML on OpenShift${COLOR_RESET}"
echo ""

wait

######################################################################
# Section functions
######################################################################

section_1() {
begin_section 1 "🔍" "Check Current State" || return 0
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

pe "oc get nodes -l nvidia.com/gpu.present=true -o custom-columns='NODE:.metadata.name,TAINT:.spec.taints[*].key,EFFECT:.spec.taints[*].effect'"

echo ""
echo "# 🚫 These GPU nodes are tainted: nvidia.com/gpu=NoSchedule"
echo "#   • Set by the MachineSet -- nodes come up pre-tainted"
echo "#   • GPU Operator pods tolerate it (they have to run there)"
echo "#   • Everything else is blocked → protects expensive GPU nodes"
echo "#   • We'll need a HardwareProfile later to let ML workloads in"

wait
}

section_2() {
begin_section 2 "🔎" "Node Feature Discovery (NFD)" || return 0
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

pe "oc describe node \$(oc get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.name}') | grep -E 'pci-10de|kernel-version.full|os_release.ID|cpu-model.vendor'"

wait
}

section_3() {
begin_section 3 "🎮" "NVIDIA GPU Operator" || return 0
echo "#"
echo "# 🔧 One operator, entire GPU stack:"
echo "#   • Drivers, device plugins, container toolkit, monitoring"
echo "#   • All driven by a single CR: ClusterPolicy"

wait

pe "oc get clusterpolicy"

echo ""
echo "# 📋 What does the ClusterPolicy configure?"

wait

pe "bat --style=grid,numbers manifests/gpu-cluster-policy.yaml"

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
}

section_4() {
begin_section 4 "📦" "Install Red Hat OpenShift AI" || return 0
echo "#"
echo "# 🧠 RHOAI = the ML platform layer on top of OpenShift"
echo "#   • Workbenches, model serving, pipelines, model registry"
echo "#   • Model Catalog with pre-validated foundation models"
echo "#   • LlamaStack for GenAI inference and chat"
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

pe "oc get csv -n redhat-ods-operator | grep rhods"

verify_step "RHOAI operator CSV is Succeeded" "oc get csv -n redhat-ods-operator 2>/dev/null | grep rhods | grep -q Succeeded"

echo ""
echo "# 🧩 The operator is installed, but it doesn't DO anything yet."
echo "#   We need a DataScienceCluster (DSC) -- the CR that tells"
echo "#   the operator which components to activate."
echo "#"
echo "# 📋 DSC components we need:"
echo "#   • Dashboard, Workbenches, ModelRegistry → Managed (defaults)"
echo "#   • KServe → Managed (model serving)"
echo "#   • DataSciencePipelines → Managed (ML pipelines)"
echo "#   • LlamaStack → Managed (NOT default -- must enable)"
echo "#   • ModelMeshServing → Removed (deprecated, KServe replaces it)"

wait

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Create DataScienceCluster${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 OpenShift Console → Installed Operators → Red Hat OpenShift AI"
echo "#   → 'DataScienceCluster' tab → Click 'Create DataScienceCluster'"
echo "#   → Switch to YAML view"
echo "#"
echo "# 📝 Find the llamastackoperator section and change it:"
echo "#     llamastackoperator:"
echo "#       managementState: Managed     ← change from Removed to Managed"
echo "#"
echo "# 💡 All other defaults are fine (Dashboard, KServe, Workbenches,"
echo "#   ModelRegistry, Pipelines are already Managed by default)"
echo "#"
echo "#   → Click 'Create'"
echo "#   → ⏳ Wait for status: Phase = Ready (may take 2-3 minutes)"
echo "#"
echo -e "# ${RED}   DO NOT press ENTER until the DSC shows Phase: Ready${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo "# 🔄 Checking RHOAI readiness..."
verify_step "DataScienceCluster exists" "oc get datasciencecluster default-dsc 2>/dev/null"
verify_step "DataScienceCluster phase is Ready" "oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null | grep -q Ready"
verify_step "Dashboard is ready" "oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type==\"DashboardReady\")].status}' 2>/dev/null | grep -q True"
verify_step "KServe is ready" "oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type==\"KserveReady\")].status}' 2>/dev/null | grep -q True"
verify_step "Workbenches ready" "oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type==\"WorkbenchesReady\")].status}' 2>/dev/null | grep -q True"
verify_step "RHOAI Dashboard gateway exists" "oc get gateway data-science-gateway -n openshift-ingress 2>/dev/null"

pe "RHOAI_URL=https://\$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].hostname}') && echo \$RHOAI_URL"

echo ""
echo "# 📋 What's managed vs removed:"

wait

pe "oc get datasciencecluster -o yaml | grep -A1 managementState"

echo ""
echo "# ✅ RHOAI 3.0 is ready -- all components healthy, LlamaStack enabled"

wait
}

section_5() {
begin_section 5 "🛡️ " "Hardware Profile with GPU Toleration" || return 0
# Depends on: RHOAI installed, RHOAI_URL set (Section 4)
verify_step "RHOAI operator is installed" "oc get csv -A 2>/dev/null | grep rhods | grep -q Succeeded"
ensure_var RHOAI_URL "echo https://\$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].hostname}')"
echo "#"
echo "# 🔑 Remember the GPU taint from Section 1?"
echo "#   • HardwareProfile is how RHOAI workloads get past it"
echo "#   • Defines: CPU + Memory + GPU requests"
echo "#   • Includes toleration so pods CAN schedule on tainted GPU nodes"

wait

echo ""
echo "# 📋 Here's what the HardwareProfile looks like:"

wait

pe "bat --style=grid,numbers manifests/hardware-profile.yaml"

echo ""
echo "# 🔧 Two ways to create this profile:"
echo "#"
echo "#   Option A: Apply the manifest (oc apply)"
echo "#   Option B: Create it manually in the RHOAI Dashboard"
echo "#     → Settings → Hardware profiles → 'Create hardware profile'"
echo "#     → Name: nvidia-gpu"
echo "#     → Add identifiers: CPU (2 default), Memory (8Gi), nvidia.com/gpu (1)"
echo "#     → Add toleration: key=nvidia.com/gpu, effect=NoSchedule, operator=Exists"
echo ""
read -p "  Apply manifest now? (y/n): " HP_CHOICE
if [ "$HP_CHOICE" = "y" ]; then
  pe "oc apply -f manifests/hardware-profile.yaml"
else
  echo ""
  echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
  echo -e "# ${RED}   ACTION REQUIRED -- Create HardwareProfile in RHOAI Dashboard${COLOR_RESET}"
  echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
  echo "#"
  echo "# 🌐 RHOAI Dashboard → Settings → Hardware profiles"
  echo "#   → Click 'Create hardware profile'"
  echo "#   → Name: nvidia-gpu"
  echo "#   → Add identifiers:"
  echo "#     • CPU:            default=2, min=1, max=8"
  echo "#     • Memory:         default=8Gi, min=2Gi, max=32Gi"
  echo "#     • nvidia.com/gpu: default=1, min=1, max=2 (type: Accelerator)"
  echo "#   → Node scheduling → Add toleration:"
  echo "#     • Key: nvidia.com/gpu"
  echo "#     • Effect: NoSchedule"
  echo "#     • Operator: Exists"
  echo "#   → Click 'Create'"
  echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
  wait
fi

echo ""
verify_step "HardwareProfile 'nvidia-gpu' exists" "oc get hardwareprofile nvidia-gpu -n redhat-ods-applications 2>/dev/null"
verify_manifest "HardwareProfile config" "manifests/hardware-profile.yaml"

wait

pe "$BROWSER_OPEN \$RHOAI_URL"

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Verify HardwareProfile in browser${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 RHOAI Dashboard → Settings → Hardware profiles"
echo "#   → 'NVIDIA GPU (A10G)' should appear"
echo "#   → Click it to verify:"
echo "#     • CPU: 2 (1-8)"
echo "#     • Memory: 8Gi (2Gi-32Gi)"
echo "#     • nvidia.com/gpu: 1 (1-2)"
echo "#     • Toleration: nvidia.com/gpu NoSchedule"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait
}

section_6() {
begin_section 6 "🌟" "Model Catalog — Deploy Granite LLM" || return 0
# Depends on: RHOAI installed (Section 4), HardwareProfile (Section 5)
ensure_var RHOAI_URL "echo https://\$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].hostname}')"
verify_step "HardwareProfile exists" "oc get hardwareprofile nvidia-gpu -n redhat-ods-applications 2>/dev/null"
echo "#"
echo "# 🌟 RHOAI includes a Model Catalog of pre-validated models"
echo "#   • Red Hat AI Validated: tested, supported, enterprise-ready"
echo "#   • Delivered as OCI ModelCar container images"
echo "#   • One-click deploy from the Dashboard"
echo "#"
echo "# 📦 ModelCar = model weights packaged as an OCI container image"
echo "#   • Uses the same OCI standard as application containers"
echo "#   • Pulled, cached, and distributed by the container runtime"
echo "#   • Immutable, version-tagged, stored in any container registry"
echo "#   • No S3 or external storage required for deployment"
echo "#   • Not just for catalog models -- you can package your own"
echo "#     production models as ModelCar images too"
echo "#"
echo "# 🎯 We'll deploy Granite 3.1 8B Instruct (W4A16 quantized)"
echo "#   • IBM's enterprise LLM -- instruction-tuned for chat"
echo "#   • W4A16 = 4-bit weights, 16-bit activations"
echo "#   • Fits easily on our A10G (24GB VRAM)"
echo "#   • Served via vLLM -- high-performance LLM inference engine"

wait

pe "$BROWSER_OPEN \$RHOAI_URL"

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Create granite-demo project${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 RHOAI Dashboard → 'Data Science Projects' (left sidebar)"
echo "#   → Click 'Create data science project'"
echo "#   → Name: granite-demo"
echo "#   → Click 'Create'"
echo "#"
echo "# 💡 A Data Science Project = an OpenShift namespace with RHOAI labels."
echo "#   The deploy dialog can only target existing projects."
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Deploy Granite from Model Catalog${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 RHOAI Dashboard → Model Catalog (left sidebar)"
echo "#   → Browse the catalog -- show the audience what's available"
echo "#   → Find: Granite 3.1 8B Instruct (quantized W4A16)"
echo "#   → Click the model card → review description, license"
echo "#   → Click 'Deploy'"
echo "#"
echo "# 📝 Deployment settings:"
echo "#   → Model name:       granite-llm"
echo "#   → Project:           granite-demo (created above)"
echo "#   → Serving runtime:   vLLM NVIDIA GPU ServingRuntime for KServe"
echo "#   → Hardware profile:  nvidia-gpu (NVIDIA GPU A10G)"
echo "#   → Model location:    should be pre-filled from catalog"
echo "#     oci://registry.redhat.io/rhelai1/modelcar-granite-3-1-8b-instruct-quantized-w4a16:1.5"
echo "#   → Advanced settings:"
echo "#     • External route: UNCHECKED (internal only)"
echo "#     • Token auth: UNCHECKED"
echo "#   → Click 'Deploy'"
echo "#"
echo "# ⏳ The model image will start pulling. This takes a few minutes"
echo "#   if not pre-warmed. We'll fill the time in the next section!"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo "# 🔄 Verify the deployment started:"

wait

pe "oc get inferenceservice -n granite-demo"

echo ""
echo "# ⏳ Model is pulling/loading. Let's talk about serving runtimes"
echo "#   and backing services while we wait..."

wait
}

section_7() {
begin_section 7 "🔧" "Serving Runtimes & Backing Services" || return 0
# Depends on: RHOAI installed (Section 4)
verify_step "RHOAI operator is installed" "oc get csv -A 2>/dev/null | grep rhods | grep -q Succeeded"
ensure_var RHOAI_URL "echo https://\$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].hostname}')"
echo "#"
echo "# 🖥️  Serving Runtimes = how models run on GPUs"
echo "#   • RHOAI supports multiple runtimes for different use cases"
echo "#   • vLLM: high-performance LLM inference (what Granite uses)"
echo "#   • Triton: multi-framework ML inference (TF, ONNX, PyTorch)"
echo "#   • Each runtime is an OpenShift Template in redhat-ods-applications"
echo "#"
echo "# 📦 RHOAI 3.0 stores runtimes as OpenShift Templates"
echo "#   • Dashboard discovers them in redhat-ods-applications"
echo "#   • Template wraps a bare ServingRuntime + metadata:"
echo "#     - API protocol (REST vs gRPC)"
echo "#     - Model type (predictive vs generative AI)"

wait

echo ""
echo "# 🔧 vLLM is already available (built into RHOAI 3.0)"
echo "#   We used it to deploy Granite in the previous section."
echo "#"
echo "# 📋 Now let's add Triton for custom ML models (TensorFlow, etc.)"
echo "#   We'll use this later when we deploy our own trained model."

wait

echo ""
echo "# 📋 Here's the Triton ServingRuntime definition:"

wait

pe "bat --style=grid,numbers manifests/serving-runtime.yaml"

echo ""
echo "# 🔧 Two ways to create this runtime:"
echo "#"
echo "#   Option A: Apply the Template manifest (oc apply)"
echo "#     → Applies the pre-wrapped Template directly"
echo "#"
echo "#   Option B: Paste bare YAML in the RHOAI Dashboard"
echo "#     → Dashboard asks for protocol + model type, wraps it for you"
echo ""
read -p "  Apply template manifest now? (y/n): " SR_CHOICE
if [ "$SR_CHOICE" = "y" ]; then
  pe "oc apply -f manifests/serving-runtime-template.yaml"
else
  echo ""
  echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
  echo -e "# ${RED}   ACTION REQUIRED -- Create ServingRuntime in RHOAI Dashboard${COLOR_RESET}"
  echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
  echo "#"
  echo "# 📁 YAML to paste: manifests/serving-runtime.yaml"
  echo "#    (scroll up or open in another terminal)"
  echo "#"
  echo "# 🌐 RHOAI Dashboard → Settings → Serving runtimes"
  echo "#   → Click 'Add serving runtime'"
  echo "#   → API protocol: REST"
  echo "#     (Triton config uses HTTP only -- --allow-grpc=false)"
  echo "#   → Model type: Predictive model"
  echo "#     (traditional ML: TensorFlow/Keras/ONNX, not LLM inference)"
  echo "#   → Select 'Start from scratch'"
  echo "#   → Paste the full YAML from manifests/serving-runtime.yaml"
  echo "#   → Click 'Create'"
  echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
  wait
fi

echo ""
verify_step "ServingRuntime template exists" "oc get template triton-kserve-gpu-template -n redhat-ods-applications 2>/dev/null"

echo ""
echo "# ✅ Two serving runtimes available:"
echo "#   • vLLM → LLMs (Granite, Llama, Mistral)"
echo "#   • Triton → custom ML (TensorFlow, ONNX, PyTorch)"

wait

echo ""
echo "# 🧱 Now let's check the backing services (deployed during setup):"
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
verify_step "MinIO pod is Running" "oc get pods -l app=minio -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"
verify_step "Model Registry DB pod is Running" "oc get pods -n rhoai-model-registry -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"

echo ""
echo "# 🪣 Time to create our model storage bucket in MinIO!"
echo "#   → This is where our custom trained models will land"

wait

verify_step "MinIO UI route exists" "oc get route minio-ui 2>/dev/null"

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

echo ""
echo "# 🔄 Let's check on the Granite deployment while we're here:"

wait

pe "oc get inferenceservice -n granite-demo"

echo ""
echo "# 💡 While Granite loads, a look at model storage:"
echo "#   • S3 (MinIO, AWS, Ceph) → fast iteration during development"
echo "#   • OCI ModelCar images → immutable, versioned, production-ready"
echo "#   • Any model can use either path -- catalog models just ship as ModelCar"

wait
}

section_8() {
begin_section 8 "💬" "LlamaStack + Chat with Granite" || return 0
# Depends on: RHOAI installed with LlamaStack (Section 4), Granite deployed (Section 6)
ensure_var RHOAI_URL "echo https://\$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].hostname}')"
echo "#"
echo "# 💬 LlamaStack = unified API for LLM inference"
echo "#   • Open-source project by Meta, supported by Red Hat"
echo "#   • Provides a standard API for chat, completions, embeddings"
echo "#   • The operator was enabled in the DSC back in Section 4"
echo "#   • Now we deploy an INSTANCE pointing at our Granite model"
echo "#   • Plus a Playground UI for interactive chat"

wait

echo ""
echo "# 🔄 First, let's make sure Granite is ready:"

wait

pe "oc get inferenceservice -n granite-demo"

verify_step "Granite InferenceService is Ready" "oc get inferenceservice -n granite-demo -o jsonpath='{.items[0].status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null | grep -q True"

echo ""
echo "# 🎯 Granite is serving! Let's set up the chat playground."

wait

# Get the Granite internal endpoint
GRANITE_ISVC=$(oc get inferenceservice -n granite-demo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
GRANITE_ENDPOINT="http://${GRANITE_ISVC}-predictor.granite-demo.svc.cluster.local:8080/v1"

# Get the model ID that vLLM is serving (needed for LlamaStack config)
GRANITE_MODEL_ID=$(oc exec -n granite-demo deploy/${GRANITE_ISVC}-predictor -c kserve-container -- curl -s http://localhost:8080/v1/models 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null) || GRANITE_MODEL_ID="granite"

echo ""
echo "# 🔗 Granite internal endpoint:"
echo "#   ${GRANITE_ENDPOINT}"
echo "#   Model ID: ${GRANITE_MODEL_ID}"

wait

echo ""
echo "# 🔧 Step 1: Deploy LlamaStack operator instance"
echo "#   • Creates a LlamaStackDistribution CR"
echo "#   • The RHOAI-managed operator sees this CR and deploys:"
echo "#     - LlamaStack API server (port 8321)"
echo "#     - ConfigMap with model routing config"
echo "#   • Uses a Helm chart from the GenAIOps Helm repo"

wait

echo ""
echo "# 📋 Installing LlamaStack operator instance via Helm..."

wait

pe "helm install llama-stack-instance genaiops/llama-stack-operator-instance \
  --namespace granite-demo \
  --set models[0].name=${GRANITE_MODEL_ID} \
  --set models[0].url=${GRANITE_ENDPOINT} \
  --set telemetry.enabled=false \
  --set otelCollector.enabled=false \
  --set rag.enabled=false \
  --set mcp.enabled=false \
  --set mcp_aihub.enabled=false \
  --set eval.enabled=false \
  --set guardrails.enabled=false"

echo ""
echo "# ⏳ Waiting for LlamaStack API server to start..."

wait

verify_step "LlamaStack pod is Running" "oc get pods -n granite-demo -l app.kubernetes.io/name=llama-stack -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"

echo ""
echo "# 🔧 Step 2: Deploy LlamaStack Playground UI"
echo "#   • Streamlit-based chat interface"
echo "#   • Connects to the LlamaStack API service"
echo "#   • Creates an OpenShift Route for browser access"

wait

pe "helm install llama-stack-playground genaiops/llama-stack-playground \
  --namespace granite-demo \
  --set playground.llamaStackUrl=http://llama-stack:8321 \
  --set playground.defaultModel=${GRANITE_MODEL_ID} \
  --set route.enabled=true \
  --set networkPolicy.enabled=false"

echo ""
echo "# ⏳ Waiting for Playground to start..."

wait

verify_step "Playground pod is Running" "oc get pods -n granite-demo -l app.kubernetes.io/name=llama-stack-playground -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"

echo ""
echo "# 🌐 Opening the Playground..."

wait

pe "PLAYGROUND_URL=\$(oc get route -n granite-demo -l app.kubernetes.io/name=llama-stack-playground -o jsonpath='https://{.items[0].spec.host}') && echo \$PLAYGROUND_URL"

pe "$BROWSER_OPEN \$PLAYGROUND_URL"

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Chat with Granite!${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 In the Playground:"
echo "#   → Select model: ${GRANITE_MODEL_ID}"
echo "#   → Try these FSI-relevant prompts:"
echo "#"
echo "#   💬 'Explain the key components of Basel III capital requirements'"
echo "#   💬 'What are the main risks in algorithmic trading?'"
echo "#   💬 'Summarize PCI-DSS compliance requirements for payment processing'"
echo "#   💬 'What is model risk management and why does it matter in banking?'"
echo "#"
echo "# 🔑 Key points for the audience:"
echo "#   • This model is running on our A10G GPU, on OpenShift"
echo "#   • Enterprise-grade: Red Hat validated, IBM-developed"
echo "#   • No data leaves the cluster -- internal inference only"
echo "#   • From catalog browse to live chat in minutes"
echo "#   • LlamaStack provides a standard API -- swap models without"
echo "#     changing your application code"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo "# ✅ Foundation model deployed from catalog and serving live!"
echo "#   Next: build and deploy your OWN custom model"

wait
}

section_9() {
begin_section 9 "🧪" "Workbench & Train Custom Model" || return 0
# Depends on: RHOAI_URL (Section 4), MINIO_URL (Section 7),
#             HardwareProfile (Section 5), ServingRuntime (Section 7)
ensure_var RHOAI_URL "echo https://\$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].hostname}')"
ensure_var MINIO_URL "oc get route minio-ui -o jsonpath='https://{.spec.host}'"
verify_step "HardwareProfile exists" "oc get hardwareprofile nvidia-gpu -n redhat-ods-applications 2>/dev/null"
verify_step "ServingRuntime template exists" "oc get template triton-kserve-gpu-template -n redhat-ods-applications 2>/dev/null"
echo "#"
echo "# 🔀 Shift: from foundation models → building your own"
echo "#   • Granite gave us GenAI out of the box"
echo "#   • But FSI needs custom models too:"
echo "#     fraud detection, credit scoring, risk pricing"
echo "#   • Same platform, same GPUs, different workflow"
echo "#"
echo "# 🎯 Interactive ML workflow:"
echo "#   1️⃣  Create Data Science Project"
echo "#   2️⃣  Connect S3 storage"
echo "#   3️⃣  Launch GPU workbench"
echo "#   4️⃣  Train model + upload to MinIO"

wait

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
echo "# ⚙️  While we're here, let's deploy the pipeline server"
echo "#   so it's ready when we get to Section 12."
echo "#   This takes a couple minutes to start up."

wait

pe "oc apply -f manifests/dspa.yaml"

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Create S3 Connection${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 2️⃣  Inside fsi-demo project → 'Connections' tab"
echo "#   → Click 'Create connection'"
echo "#   → Connection type: S3 compatible object storage - v1"
echo "#   → Connection name:  minio-models"
echo "#   → Access key:       minio"
echo "#   → Secret key:       minio123"
echo "#   → Endpoint:         http://minio-service.default.svc.cluster.local:9000"
echo "#   → Bucket:           models"
echo "#   → Click 'Create'"
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
echo "#   → Connections → check 'Attach existing connections'"
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
echo "# 4️⃣  In JupyterLab terminal, clone the repo:"
echo "#   → git clone https://github.com/adam-d-young/RHOAI-demo.git"
echo "#   → Navigate to RHOAI-demo/notebooks/"
echo "#   → Run in order:"
echo "#"
echo "#   📓 gpu-check.py        → Can TensorFlow see the A10G?"
echo "#   📓 gpu-demo.py         → GPU matrix multiply"
echo "#   📓 train-and-upload.py → Train model, upload to MinIO"
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
echo "#   → You should see: production/demo-model/"
echo "#     → config.pbtxt"
echo "#     → 1/model.savedmodel/saved_model.pb"
echo "#     → 1/model.savedmodel/fingerprint.pb"
echo "#     → 1/model.savedmodel/variables/"
echo "#"
echo "# ✅ Model trained on GPU, exported, and stored in S3"
echo "#   Next: register it in the Model Registry before deploying"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait
}

section_10() {
begin_section 10 "📋" "Model Registry" || return 0
# Depends on: RHOAI installed (Section 4), Model trained (Section 9),
#             MySQL DB deployed (setup.sh Step 8)
ensure_var RHOAI_URL "echo https://\$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].hostname}')"
verify_step "RHOAI operator is installed" "oc get csv -A 2>/dev/null | grep rhods | grep -q Succeeded"
verify_step "Model Registry DB is running" "oc get pods -n rhoai-model-registry -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"
echo "#"
echo "# 🗂️  Model Registry = the catalog for YOUR models"
echo "#   • NOT the Model Catalog (pre-built Red Hat AI models)"
echo "#   • Tracks: name, version, description, artifact URI"
echo "#   • Add custom properties: team, regulatory, risk tier"
echo "#   • Deploy directly from the registry"
echo "#   • Full audit trail: who trained it, when, what data"
echo "#"
echo "# 📋 In production (FSI), this is critical:"
echo "#   • Model Risk Management (SR 11-7 / SS1/23)"
echo "#   • Version control for model governance"
echo "#   • Deployment tracking across environments"

wait

echo ""
echo "# 🔧 First, create the Model Registry instance"
echo "#   • The RHOAI operator installs the registry capability"
echo "#   • But we still need to create an actual registry instance"
echo "#   • It connects to our MySQL backend (deployed in setup)"

wait

echo ""
echo "# 📋 Here's the registry instance manifest:"

wait

pe "bat --style=grid,numbers manifests/model-registry-instance.yaml"

wait

pe "oc apply -f manifests/model-registry-instance.yaml"

echo ""
echo "# ⏳ Waiting for registry to become available..."

wait

pe "oc wait --for=condition=Available mr/fsi-model-registry -n rhoai-model-registries --timeout=120s"

verify_step "Model Registry instance is Available" "oc get mr fsi-model-registry -n rhoai-model-registries -o jsonpath='{.status.conditions[?(@.type==\"Available\")].status}' 2>/dev/null | grep -q True"

echo ""
echo "# ✅ Registry is live! Now register our trained model"

wait

pe "$BROWSER_OPEN \$RHOAI_URL"

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Register model in Model Registry${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 RHOAI Dashboard → 'Model Registry' in left sidebar"
echo "#   → Select registry: fsi-model-registry"
echo "#   → Click 'Register model'"
echo "#"
echo "# 📝 Model details:"
echo "#   → Model name:        fsi-fraud-detection"
echo "#   → Model description:"
echo "#     Binary classifier for real-time transaction fraud detection."
echo "#     5-feature input (amount, category, time delta, account age,"
echo "#     frequency). Sigmoid output (0-1), >0.5 = suspected fraud."
echo "#"
echo "# 📦 Version details:"
echo "#   → Version name:      v1.0"
echo "#   → Version description:"
echo "#     Initial release. Trained on 100K synthetic transactions."
echo "#     Architecture: 5→10(ReLU)→1(Sigmoid). Validation AUC: 0.94."
echo "#"
echo "# 🔗 Model location:"
echo "#   → Source model format:  tensorflow"
echo "#   → Source model version: 2"
echo "#   → Model location (URI): s3://models/production/demo-model/"
echo "#"
echo "#   → Click 'Register model'"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Add custom properties${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 Click into 'fsi-fraud-detection' → 'v1.0' version"
echo "#   → Look for 'Properties' or 'Custom properties' section"
echo "#   → Add these key-value pairs:"
echo "#"
echo "#   Key                    Value"
echo "#   ─────────────────────  ──────────────────────────────────"
echo "#   team                   FSI Risk Analytics"
echo "#   use_case               Real-time fraud detection"
echo "#   regulatory_framework   PCI-DSS, SOX"
echo "#   data_classification    Confidential - PII Adjacent"
echo "#   owner                  Adam Young"
echo "#   gpu_type               NVIDIA A10G (24GB VRAM)"
echo "#   serving_runtime        NVIDIA Triton 24.01"
echo "#   training_dataset       synthetic_transactions_100k"
echo "#   validation_auc         0.94"
echo "#   risk_tier              Tier 2 - Model risk review complete"
echo "#   approval_status        Approved for staging"
echo "#"
echo "# 💡 Why this matters in FSI:"
echo "#   • Regulators can audit which model version is in production"
echo "#   • Risk teams see validation metrics + approval status"
echo "#   • Data governance tracks PII-adjacent classifications"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo "# ✅ Model registered with full metadata"
echo "#   Next: deploy it directly from the registry"

wait
}

section_11() {
begin_section 11 "🚀" "Deploy from Registry & Test Inference" || return 0
# Depends on: Model registered (Section 10), ServingRuntime (Section 7)
ensure_var RHOAI_URL "echo https://\$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].hostname}')"
verify_step "ServingRuntime template exists" "oc get template triton-kserve-gpu-template -n redhat-ods-applications 2>/dev/null"
echo "#"
echo "# 🚀 Deploy directly from the Model Registry"
echo "#   • The registry knows the artifact URI, format, and version"
echo "#   • Deployment is tracked -- shows up in the registry's Deployments tab"
echo "#   • Full lineage: trained → registered → deployed → serving"

wait

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Deploy model from registry${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 RHOAI Dashboard → Model Registry → fsi-model-registry"
echo "#   → Click 'fsi-fraud-detection'"
echo "#   → On version 'v1.0' row → click 'Deploy' (kebab menu or button)"
echo "#"
echo "# 📝 Deployment settings:"
echo "#   → Model name:       fsi-demo-model"
echo "#   → Project:           fsi-demo"
echo "#   → Serving runtime:   Triton Inference Server (GPU)"
echo "#   → Model framework:   tensorflow - 2"
echo "#   → Model location:    should be pre-filled from registry"
echo "#     (if not: Existing connection → minio-models, path: production)"
echo "#   → Advanced settings:"
echo "#     • External route: UNCHECKED"
echo "#     • Token auth: UNCHECKED"
echo "#   → Click 'Deploy'"
echo "#   → ⏳ Wait for status: ✅ green checkmark"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo "# 🔄 Verify deployment from CLI while we wait:"

wait

pe "oc get inferenceservice -n fsi-demo"

# Capture the InferenceService name (Dashboard may auto-generate it from registry)
ISVC_NAME=$(oc get inferenceservice -n fsi-demo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
echo ""
echo "# ⏳ Waiting for model to load on GPU..."
echo "#   InferenceService name: ${ISVC_NAME:-unknown}"

verify_step "InferenceService is Ready" "oc get inferenceservice -n fsi-demo -o jsonpath='{.items[0].status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null | grep -q True"

echo ""
echo "# 🔍 Check the registry -- Deployments tab should now show this deployment"
echo "#   → Go back to Model Registry → fsi-fraud-detection"
echo "#   → Click 'Deployments' tab"
echo "#   → ${ISVC_NAME:-the deployment} should appear with status"

wait

echo ""
echo "# ✅ Model deployed from registry with full lineage tracking"
echo "#   Now let's send some predictions!"

wait

echo ""
echo "# 🎯 The payoff -- send data to the live model and get a prediction!"
echo "#   • Our model: 5 floats in → 1 sigmoid probability out"
echo "#   • Using Triton's v2 REST API from inside the cluster"
echo "#   • The notebook auto-detects the input tensor name"

wait

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Run inference notebook${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 In JupyterLab (same workbench from Section 9):"
echo "#   → Navigate to RHOAI-demo/notebooks/"
echo "#   → Open: 📓 inference-test.ipynb"
echo "#"
echo -e "# ${CYAN}✏️  FIRST: Update ISVC_NAME in the first code cell:${COLOR_RESET}"
echo "#     ISVC_NAME = \"${ISVC_NAME:-<check oc get inferenceservice>}\""
echo "#"
echo "#   → Then run each cell with Shift+Enter"
echo "#"
echo "# 💡 What it does:"
echo "#   1. Queries Triton for model metadata (auto-detects tensor names)"
echo "#   2. Sends two different prediction requests"
echo "#   3. Shows the sigmoid probability output (0-1)"
echo "#"
echo "# 🔑 In production this would be:"
echo "#   • Fraud detection scores on transactions"
echo "#   • Credit risk assessments"
echo "#   • Real-time pricing models"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo "# ✅ Full custom model lifecycle complete:"
echo "#   Train on GPU → register → deploy from registry → live inference"

wait
}

section_12() {
begin_section 12 "⚙️ " "Data Science Pipelines & Experiments" || return 0
# Depends on: RHOAI installed (Section 4), fsi-demo namespace (Section 9)
ensure_var RHOAI_URL "echo https://\$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].hostname}')"
verify_step "fsi-demo namespace exists" "oc get namespace fsi-demo 2>/dev/null"
echo "#"
echo "# ⚙️  Data Science Pipelines = automated, repeatable workflows"
echo "#   • Kubeflow Pipelines (KFP) on OpenShift"
echo "#   • Each step = a container with defined inputs/outputs"
echo "#   • Steps run in sequence or parallel on the cluster"
echo "#   • Triggered on schedule, git push, or new data"
echo "#"
echo "# 📋 A standard ML pipeline looks like:"
echo "#   1️⃣  Data Processing   → clean, normalize raw data"
echo "#   2️⃣  Feature Extract   → derive model features"
echo "#   3️⃣  Train Model       → fit on GPU, output SavedModel"
echo "#   4️⃣  Validate          → score against holdout set"
echo "#   5️⃣  Upload Model      → push artifacts to S3"
echo "#"
echo "# 💡 We did Sections 9-11 manually so you could see each step."
echo "#   In production, the training workflow is a pipeline."
echo "#   Deployment stays separate (Model Registry → Deploy)."

wait

echo ""
echo "# 🔧 Pipeline server was deployed back in Section 9."
echo "#   Let's verify it's ready:"

wait

verify_step "DSPA is Ready" "oc get dspa dspa -n fsi-demo -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null | grep -q True"

pe "oc get dspa -n fsi-demo"

wait

echo ""
echo "# 🔧 Step 1: Compile the pipeline"
echo "#   • Pipeline is written in Python using KFP v2 SDK"
echo "#   • Each @dsl.component becomes a container step"
echo "#   • Compiling produces an IR YAML (Intermediate Representation)"
echo "#"
echo "# 📋 What is IR YAML?"
echo "#   • Platform-agnostic pipeline specification"
echo "#   • Python SDK → compiles → IR YAML → imported into RHOAI"
echo "#   • The DSPA backend translates IR YAML into an Argo Workflow"
echo "#   • Same IR works on any KFP v2-compatible backend"
echo "#"
echo "# 📋 Our pipeline has 4 steps (we'll add the 5th with Elyra):"
echo "#   data-processing → feature-extract → train-model → upload-model"

wait

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Compile pipeline in workbench${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 In JupyterLab terminal (same workbench from Section 9):"
echo "#   → Make sure you're in the RHOAI-demo/notebooks/ directory"
echo "#   → Run:"
echo "#"
echo "#     pip install kfp"
echo "#     python fsi-fraud-pipeline.py"
echo "#"
echo "#   → This generates: fsi-fraud-pipeline.yaml (the IR YAML)"
echo "#   → You should see: 'Pipeline compiled to: fsi-fraud-pipeline.yaml'"
echo "#"
echo "#   💡 The Python code defines the pipeline declaratively."
echo "#     The compiler serializes it to IR YAML -- the portable format"
echo "#     that any KFP v2 backend can execute."
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo "# 🔧 Step 2: Import and run the 4-step pipeline"

wait

pe "$BROWSER_OPEN \$RHOAI_URL"

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Import pipeline in RHOAI Dashboard${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 RHOAI Dashboard → fsi-demo project → 'Pipelines' tab"
echo "#   → Click 'Import pipeline'"
echo "#   → Pipeline name: FSI Fraud Detection Training"
echo "#   → Upload: fsi-fraud-pipeline.yaml (the IR YAML from workbench)"
echo "#     (download from JupyterLab or copy/paste)"
echo "#   → Click 'Import pipeline'"
echo "#"
echo "# 🏃 Then create a run:"
echo "#   → Click the pipeline name → 'Create run'"
echo "#   → Run name: fraud-training-run-1"
echo "#   → Experiment: Create new → 'fsi-fraud-experiments'"
echo "#   → Parameters: num_samples = 10000 (default)"
echo "#   → Click 'Create'"
echo "#"
echo "# 👀 Watch the pipeline execute:"
echo "#   → Each step lights up as it runs"
echo "#   → Click a step to see its logs"
echo "#   → 4 steps run in sequence:"
echo "#     data-processing → feature-extract → train-model → upload-model"
echo "#"
echo "# 💡 Notice: there's no validation step yet!"
echo "#   We'll add that next using the Elyra visual editor."
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo "# 🎨 Step 3: Add Validate step with Elyra"
echo "#   • Elyra = visual pipeline editor in JupyterLab"
echo "#   • Drag-and-drop nodes instead of writing Python"
echo "#   • Each node = a notebook or Python script"
echo "#   • Two ways to build pipelines:"
echo "#     Code-first: KFP SDK (what we just did)"
echo "#     Visual: Elyra (what we're doing now)"

wait

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Add Validate step in Elyra${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 In JupyterLab (same workbench):"
echo "#   → File menu → New → Pipeline Editor"
echo "#   → This opens the Elyra visual pipeline canvas"
echo "#"
echo "# 🧩 Add the validate step:"
echo "#   → From the file browser, drag validate-model.ipynb"
echo "#     onto the pipeline canvas"
echo "#   → This creates a node for the validation script"
echo "#   → Right-click the node → Properties to configure:"
echo "#     • Runtime image: pick a Python image"
echo "#     • Dependencies: numpy, scikit-learn"
echo "#"
echo "# 💡 Elyra lets data scientists build pipelines"
echo "#   without writing KFP SDK code. Each node is a"
echo "#   notebook or script -- drag, drop, connect, run."
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo "# 📊 Step 4: Experiments & Tracking"
echo "#   • Pipeline runs can be used as experiments"
echo "#   • The run view tracks those experiments"
echo "#   • Compare results across runs, reproduce any previous run"

wait

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Explore Experiments${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 RHOAI Dashboard → fsi-demo project → 'Experiments' tab"
echo "#   → Click 'fsi-fraud-experiments'"
echo "#   → Shows all runs in this experiment"
echo "#   → Click a completed run to see:"
echo "#     • DAG visualization (pipeline graph)"
echo "#     • Per-step logs (training accuracy, AUC score)"
echo "#     • Input/output artifacts"
echo "#     • Run parameters and duration"
echo "#"
echo "# 💡 In production:"
echo "#   • Run the pipeline on new data → automatic retraining"
echo "#   • Compare AUC scores across experiments"
echo "#   • Promote best model to Model Registry → Deploy"
echo "#   • Schedule pipelines to run on a cadence"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo "# ✅ Pipeline deployed, run complete, experiment tracked"
echo "#   Manual workflow (Sections 9-11) is now automated"

wait
}

section_13() {
echo ""
echo -e "# 🎉 ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
echo "#"
echo -e "#   ${GREEN}Demo complete!${COLOR_RESET}"
echo "#"
echo "#   What we covered:"
echo "#"
echo "#   🔧 GPU Infrastructure"
echo "#   • NFD + NVIDIA GPU Operator on OpenShift"
echo "#   • Hardware Profiles with GPU tolerations"
echo "#"
echo "#   🌟 Foundation Models (GenAI)"
echo "#   • Model Catalog with pre-validated models"
echo "#   • One-click Granite LLM deployment via vLLM"
echo "#   • LlamaStack chat playground"
echo "#"
echo "#   🧪 Custom ML Models"
echo "#   • GPU-accelerated training workbenches"
echo "#   • Model Registry with FSI governance metadata"
echo "#   • Deploy from registry with full lineage"
echo "#   • Live inference on A10G GPU"
echo "#"
echo "#   ⚙️  Automation"
echo "#   • Data Science Pipelines (KFP v2 + Elyra)"
echo "#   • Experiment tracking and reproducibility"
echo "#"
echo -e "#   All on ${CYAN}Red Hat OpenShift AI 3.0${COLOR_RESET} 🚀"
echo "#"
echo -e "# ${GREEN}══════════════════════════════════════════════${COLOR_RESET}"
}

######################################################################
# Run all sections
######################################################################

section_1
section_2
section_3
section_4
section_5
section_6
section_7
section_8
section_9
section_10
section_11
section_12
section_13
