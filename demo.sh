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
for tool in oc bat; do
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
echo "# 💰 GPUs are the most expensive resource in your cluster."
echo "#   Without proper scheduling and isolation, teams fight over them"
echo "#   or they sit idle. We need a stack that:"
echo "#   • Discovers GPU hardware automatically (NFD)"
echo "#   • Manages drivers, device plugins, and monitoring (GPU Operator)"
echo "#   • Controls who can schedule on GPU nodes (taints + tolerations)"

wait

pe "oc get csv -A | grep -E 'nvidia|nfd|rhods'"

echo ""
echo "# 🖥️  GPU nodes online?"

wait

pe "oc get nodes -l nvidia.com/gpu.present=true"

pe "oc get nodes -l nvidia.com/gpu.present=true -o custom-columns='NODE:.metadata.name,TAINT:.spec.taints[*].key,EFFECT:.spec.taints[*].effect'"

echo ""
echo "# 🚫 These GPU nodes are tainted: nvidia.com/gpu=NoSchedule"
echo "#   • Without this, ANY pod could land on a \$3/hr GPU node"
echo "#   • Taints block everything by default -- only approved workloads get in"
echo "#   • GPU Operator pods tolerate it (they manage the hardware)"
echo "#   • We'll create a HardwareProfile later to let ML workloads through"

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
echo "# 🧠 Problem: OpenShift gives you containers and GPUs, but"
echo "#   data scientists still need notebooks, model serving, pipelines,"
echo "#   a model registry, and a catalog of foundation models."
echo "#   Building all that from scratch is months of work."
echo "#"
echo "# 📦 RHOAI = the ML platform layer that turns OpenShift into"
echo "#   a self-service AI development environment. One operator install."
echo "#   Everything you'll use in this bootcamp -- workbenches, LlamaStack,"
echo "#   pipelines, model serving -- runs on top of this."

wait

OCP_CONSOLE=$(oc whoami --show-console)
$BROWSER_OPEN $OCP_CONSOLE

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
echo "#   • ModelMeshServing → Removed (deprecated, KServe replaces it)"

wait

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Create DataScienceCluster${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 OpenShift Console → Installed Operators → Red Hat OpenShift AI"
echo "#   → 'DataScienceCluster' tab → Click 'Create DataScienceCluster'"
echo "#"
echo "# 💡 All defaults are fine (Dashboard, KServe, Workbenches,"
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

RHOAI_URL=https://$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].hostname}')

echo ""
echo "# 📋 What's managed vs removed:"

wait

pe "oc get datasciencecluster -o yaml | grep -A1 managementState"

echo ""
echo "# ✅ RHOAI 3.0 is ready -- all components healthy"

wait
}

section_5() {
begin_section 5 "🛡️ " "Hardware Profile with GPU Toleration" || return 0
# Depends on: RHOAI installed, RHOAI_URL set (Section 4)
verify_step "RHOAI operator is installed" "oc get csv -A 2>/dev/null | grep rhods | grep -q Succeeded"
ensure_var RHOAI_URL "echo https://\$(oc get gateway data-science-gateway -n openshift-ingress -o jsonpath='{.spec.listeners[0].hostname}')"
echo "#"
echo "# 🔑 Problem: GPUs are tainted, so nothing can schedule there."
echo "#   But data scientists need GPU access for training and inference."
echo "#   How do you give ML workloads GPU access without opening"
echo "#   the floodgates to every pod in the cluster?"
echo "#"
echo "# 🛡️  HardwareProfile = RHOAI's answer"
echo "#   • Defines resource requests (CPU, memory, GPU count)"
echo "#   • Includes the toleration to get past the GPU taint"
echo "#   • Data scientists pick a profile, not raw resource numbers"

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

$BROWSER_OPEN $RHOAI_URL

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
echo "# 🌟 Problem: where do you get foundation models you can trust?"
echo "#   Public model hubs have thousands of models -- no validation,"
echo "#   no support, no supply chain security. In regulated industries"
echo "#   you need models that are tested, signed, and supported."
echo "#"
echo "# 📦 Model Catalog = Red Hat's curated model supply chain"
echo "#   • Red Hat AI Validated: tested, supported, enterprise-ready"
echo "#   • Delivered as OCI ModelCar images (same standard as containers)"
echo "#   • Immutable, version-tagged, pulled by the container runtime"
echo "#   • One-click deploy from the Dashboard -- no S3 needed"
echo "#   • You can package your own models as ModelCar images too"
echo "#"
echo "# 🎯 We'll deploy Granite 3.1 8B Instruct (W4A16 quantized)"
echo "#   • IBM's enterprise LLM -- instruction-tuned for chat"
echo "#   • W4A16 = 4-bit weights, 16-bit activations"
echo "#   • Fits on our A10G (24GB VRAM)"
echo "#   • Served via vLLM -- high-performance LLM inference engine"

wait

$BROWSER_OPEN $RHOAI_URL

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

verify_step "granite-demo namespace exists" "oc get namespace granite-demo 2>/dev/null"

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
echo "#   → Additional serving runtime arguments:"
echo "#     --max-model-len=4096"
echo "#     (default 131K context needs more KV cache than A10G 24GB can hold)"
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
echo "# 🖥️  Problem: different model types need different inference engines."
echo "#   An LLM needs token-by-token generation with KV caching (vLLM)."
echo "#   A fraud detection model needs batch tensor inference (Triton)."
echo "#   You need both on the same platform."
echo "#"
echo "# 🔧 Serving Runtimes = pluggable inference engines"
echo "#   • vLLM: LLM inference -- what Granite uses"
echo "#   • Triton: multi-framework ML (TensorFlow, ONNX, PyTorch)"
echo "#   • In the llm-d lab you'll see advanced LLM serving patterns"
echo "#     (disaggregated prefill/decode, routing, autoscaling)"
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

MINIO_URL=$(oc get route minio-ui -o jsonpath='https://{.spec.host}')

$BROWSER_OPEN $MINIO_URL

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
# Depends on: Granite deployed (Section 6)
echo "#"
echo "# 💬 Let's prove Granite is actually working -- chat with it!"
echo "#   • LlamaStack gives us a chat UI on top of the model"
echo "#   • You'll go deep on LlamaStack in the agentic and RAG labs"
echo "#   • For now, it's just here to show live inference"

wait

echo ""
echo "# 🔄 First, let's make sure Granite is ready:"

wait

pe "oc get inferenceservice -n granite-demo"

verify_step "Granite InferenceService is Ready" "oc get inferenceservice -n granite-demo -o jsonpath='{.items[0].status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null | grep -q True"

echo ""
echo "# 🎯 Granite is serving! You can see it in the RHOAI Dashboard:"
echo "#   → RHOAI Dashboard → Data Science Projects → granite-demo"
echo "#   → 'Model' tab shows the deployed model, status, and endpoint"

wait

# Get the Granite internal endpoint
GRANITE_ISVC=$(oc get inferenceservice -n granite-demo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
GRANITE_ENDPOINT="http://${GRANITE_ISVC}-predictor.granite-demo.svc.cluster.local:8080/v1"

# Get the model ID that vLLM is serving (needed for LlamaStack config)
GRANITE_MODEL_ID=$(oc exec -n granite-demo deploy/${GRANITE_ISVC}-predictor -c kserve-container -- curl -s http://localhost:8080/v1/models 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null) || GRANITE_MODEL_ID="granite"

echo ""
echo "# ⏳ Deploying LlamaStack API server + Playground..."
echo "#   (connecting to Granite at ${GRANITE_ENDPOINT})"

# Create ConfigMap with LlamaStack run.yaml config pointing to Granite
oc create configmap llama-stack-config -n granite-demo \
  --from-literal=run.yaml="$(cat <<LLCFG
version: '2'
image_name: vllm
metadata_store:
  type: sqlite
  db_path: /tmp/llama_stack_metadata.db
apis:
  - inference
models:
  - metadata: {}
    model_id: ${GRANITE_MODEL_ID}
    provider_id: vllm
    provider_model_id: ${GRANITE_MODEL_ID}
    model_type: llm
providers:
  inference:
    - provider_id: vllm
      provider_type: "remote::vllm"
      config:
        url: "${GRANITE_ENDPOINT}"
        tls_verify: false
server:
  port: 8321
LLCFG
)" --dry-run=client -o yaml 2>/dev/null | oc apply -f - 2>/dev/null

# Deploy LlamaStack server + playground
oc apply -f "${DEMO_DIR}/manifests/llama-stack.yaml" -n granite-demo 2>/dev/null
oc apply -f "${DEMO_DIR}/manifests/llama-stack-playground.yaml" -n granite-demo 2>/dev/null

# Set the correct model ID on the playground
oc set env deployment/llama-stack-playground -n granite-demo \
  DEFAULT_MODEL="${GRANITE_MODEL_ID}" 2>/dev/null

verify_step "LlamaStack server is Running" "oc get pods -n granite-demo -l app=llama-stack -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"
verify_step "Playground is Running" "oc get pods -n granite-demo -l app=llama-stack-playground -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running"

echo ""
echo "# 🌐 Opening the Playground..."

wait

PLAYGROUND_URL=$(oc get route llama-stack-playground -n granite-demo -o jsonpath='https://{.spec.host}')

$BROWSER_OPEN $PLAYGROUND_URL

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
echo "#   • In the labs you'll build RAG and agents on top"
echo "#     of this same infrastructure"
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
echo "# 🔀 Granite gave us GenAI out of the box -- but foundation"
echo "#   models can't do everything. FSI needs custom models for"
echo "#   fraud detection, credit scoring, risk pricing -- problems"
echo "#   that require your proprietary data and domain expertise."
echo "#"
echo "# 🧪 Problem: data scientists need GPU environments, but you"
echo "#   don't want them SSH'ing into bare metal or fighting over"
echo "#   shared Jupyter servers. RHOAI workbenches give each team"
echo "#   an isolated, self-service GPU environment with S3 access."
echo "#"
echo "# 🎯 Interactive ML workflow:"
echo "#   1️⃣  Create Data Science Project"
echo "#   2️⃣  Connect S3 storage"
echo "#   3️⃣  Launch GPU workbench"
echo "#   4️⃣  Train model + upload to MinIO"

wait

$BROWSER_OPEN $RHOAI_URL

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
echo "#"
echo "# 📦 The pipeline server reuses our MinIO S3 storage"
echo "#   • Same 'models' bucket we created earlier"
echo "#   • Artifacts stored under the pipeline-artifacts/ prefix"
echo "#   • No extra bucket needed -- pipelines and models share storage"
echo "#   • You can also configure this from the RHOAI Dashboard"
echo "#     (Data Science Projects → Pipelines → Configure pipeline server)"

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

$BROWSER_OPEN $MINIO_URL

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Verify model in MinIO${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 5️⃣  🌐 MinIO Console:"
echo "#   → Object Browser → 'models' bucket"
echo "#   → You should see: production/demo-model/"
echo "#     → config.pbtxt                          -- Triton serving config (inputs, outputs, platform)"
echo "#     → 1/model.savedmodel/saved_model.pb     -- TensorFlow graph (model architecture + ops)"
echo "#     → 1/model.savedmodel/fingerprint.pb     -- Model hash for version tracking"
echo "#     → 1/model.savedmodel/variables/          -- Trained weights and biases"
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
echo "# 🗂️  Problem: a model works in my notebook -- now what?"
echo "#   Who trained it? On what data? Is this the version in production?"
echo "#   In FSI, regulators ask these questions. Without answers,"
echo "#   you fail audits (SR 11-7, SS1/23, PCI-DSS)."
echo "#"
echo "# 📋 Model Registry = governance + lineage for YOUR models"
echo "#   • NOT the Model Catalog (that's pre-built Red Hat models)"
echo "#   • Tracks: name, version, artifact location, custom properties"
echo "#   • Deploy directly from the registry -- full audit trail"
echo "#   • Every deployment is linked back to a registered version"

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

$BROWSER_OPEN $RHOAI_URL

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
echo "#   → Select 'Object storage' (not URI)"
echo "#     Endpoint: http://minio-service.default.svc.cluster.local:9000"
echo "#     Bucket:   models"
echo "#     Region:   us-east-1"
echo "#     Path:     production/"
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
echo "# 🚀 Problem: how do you go from 'model works in my notebook'"
echo "#   to 'model serves production traffic on a GPU'?"
echo "#   Manually wiring up storage paths, serving runtimes, and"
echo "#   hardware profiles is error-prone and unauditable."
echo "#"
echo "# 📦 Deploy from Registry = one-click production deployment"
echo "#   • Registry pre-fills artifact URI, format, and version"
echo "#   • Deployment is tracked in the registry's Deployments tab"
echo "#   • Full lineage: trained → registered → deployed → serving"

wait

echo ""
echo "# 🔧 First, we need to free a GPU for our fraud model."
echo "#   Both A10G GPUs are currently in use:"
echo "#     GPU 1: Granite LLM (granite-demo) -- done after Section 8"
echo "#     GPU 2: Training workbench (fsi-demo) -- still needed"

wait

$BROWSER_OPEN $RHOAI_URL

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Stop the Granite deployment${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 RHOAI Dashboard → Data Science Projects → granite-demo"
echo "#   → Models tab → click the Granite model kebab menu (⋮)"
echo "#   → 'Delete model server'"
echo "#   → Confirm deletion"
echo "#"
echo "# 💡 We're done chatting -- time to deploy our own model."
echo "#   Deleting the model server frees the GPU."
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

GRANITE_ISVC=$(oc get inferenceservice -n granite-demo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) || true
if [ -n "$GRANITE_ISVC" ]; then
  echo ""
  echo "# ⏳ Waiting for Granite to scale down..."
  while oc get pods -n granite-demo -l serving.kserve.io/inferenceservice=${GRANITE_ISVC} --no-headers 2>/dev/null | grep -q Running; do
    sleep 5
  done
fi
echo -e "  ${GREEN}✅ GPU freed${COLOR_RESET}"

# Also scale down LlamaStack (no longer needed without the LLM)
oc scale deployment llama-stack llama-stack-playground -n granite-demo --replicas=0 2>/dev/null || true

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
echo "# ⚙️  Problem: we just trained and deployed a model manually."
echo "#   That works once. But what about next week when new data arrives?"
echo "#   Or when a different team needs the same workflow?"
echo "#   Manual steps don't scale, and they don't leave an audit trail."
echo "#"
echo "# 🔧 Data Science Pipelines = automated, repeatable ML workflows"
echo "#   • Kubeflow Pipelines (KFP) on OpenShift"
echo "#   • Each step = a container with defined inputs/outputs"
echo "#   • Triggered on schedule, git push, or new data"
echo "#   • Every run is tracked: parameters, logs, artifacts, duration"
echo "#"
echo "# 📋 Our pipeline automates what we did manually:"
echo "#   1️⃣  Data Processing   → generate/clean transaction data"
echo "#   2️⃣  Feature Extract   → normalize features"
echo "#   3️⃣  Train Model       → fit classifier"
echo "#   4️⃣  Upload Model      → push artifacts to S3"

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
echo "# 📋 Our pipeline has 4 steps:"
echo "#   data-processing → feature-extract → train-model → upload-model"

wait

echo ""
echo -e "# ${RED}🛑 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo -e "# ${RED}   ACTION REQUIRED -- Compile pipeline in workbench${COLOR_RESET}"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
echo "#"
echo "# 🌐 In JupyterLab (same workbench from Section 9):"
echo "#   → Navigate to RHOAI-demo/notebooks/"
echo "#   → Open: 📓 fsi-fraud-pipeline.ipynb"
echo "#   → Walk through the cells -- each one defines a pipeline step"
echo "#   → Run all cells (Shift+Enter through each)"
echo "#   → The last cell compiles and outputs: fsi-fraud-pipeline.yaml"
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

$BROWSER_OPEN $RHOAI_URL

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
echo "# 💡 In production:"
echo "#   • Submit pipelines programmatically (kfp.client.Client)"
echo "#   • Trigger from CI/CD (Tekton, GitHub Actions) on git push"
echo "#   • Schedule recurring runs (daily retraining on new data)"
echo "#   • Add validation, monitoring, and promotion steps"
echo -e "# ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"

wait

echo ""
echo "# 🎨 Note: Elyra (visual pipeline editor)"
echo "#   • RHOAI workbenches also include Elyra"
echo "#   • Drag-and-drop pipeline building -- no Python SDK needed"
echo "#   • Each node = a notebook or Python script"
echo "#   • File → New → Pipeline Editor to try it"
echo "#   • Elyra produces its own .pipeline format (separate from KFP IR YAML)"
echo "#   • You'll explore Elyra in the hands-on labs"

wait

echo ""
echo "# 📊 Step 3: Experiments & Metrics"
echo "#   • Experiments group related runs for comparison"
echo "#   • Our train step logs metrics: accuracy, AUC, dataset size"
echo "#   • Click a completed run → metrics appear in the visualization tab"
echo "#   • Compare AUC across runs to pick the best model"

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
echo "#     • Per-step logs"
echo "#     • Metrics tab: train_accuracy, test_accuracy, auc, num_samples"
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
echo -e "#   ${GREEN}That's the platform. Here's what you built today:${COLOR_RESET}"
echo "#"
echo "#   🔧 GPU infrastructure → managed by operators, protected by taints"
echo "#   🌟 Foundation model → deployed from catalog, chatting in minutes"
echo "#   🧪 Custom model → trained on GPU, registered, deployed, serving"
echo "#   ⚙️  Pipeline → automated the whole training workflow"
echo "#"
echo -e "#   ${CYAN}Coming up in the labs:${COLOR_RESET}"
echo "#"
echo "#   💬 LlamaStack deep dive → agents, tool use, agentic workflows"
echo "#   📚 RAG → ground LLMs in your own documents"
echo "#   🏢 MaaS → models as a shared service across teams"
echo "#   🚀 llm-d → disaggregated LLM serving at scale"
echo "#   🛡️  TrustyAI → model explainability and safety"
echo "#"
echo "#   Everything runs on the same platform you just saw."
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
