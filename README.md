# RHOAI Demo - Get Started with OpenShift AI

Instructor-led demo for FSI Bootcamp Day 1. Covers GPU infrastructure, Red Hat OpenShift AI installation, Model Catalog with Granite LLM, LlamaStack chat, model training, model registry, model serving, and data science pipelines.

## Prerequisites

### Cluster Environment

This demo assumes:
- **Red Hat OpenShift** on AWS, provisioned from [demo.redhat.com](https://demo.redhat.com) (OpenShift Open Environment)
- **RHOAI 3.0** (installed live during the demo)
- At least one GPU node (NVIDIA A10G recommended)

### GPU Setup

GPU infrastructure must be configured before running this demo. Use [ocp-gpu-setup](https://github.com/rh-aiservices-bu/ocp-gpu-setup) to provision:

1. GPU machineset (A10G on AWS)
2. Node Feature Discovery (NFD) operator v4.20.0
3. NVIDIA GPU Operator v25.3.0
4. Custom resources (ClusterPolicy, NFD config, driver spec)

Clone sibling repos alongside this one:

```
your-workspace/
  ocp-gpu-setup/          # GPU infrastructure setup
  RHOAI-demo/             # This repo
```

LlamaStack is deployed as bare Kubernetes resources (no operator or Helm charts) using `eformat` container images that are compatible with each other.

### Tools

- `oc` CLI, logged into the target cluster
- `bat` (syntax-highlighted file viewer) -- `brew install bat`

## Repo Structure

```
RHOAI-demo/
├── demo-magic.sh                          # demo-magic library (typewriter effect)
├── setup.sh                               # Pre-demo cluster setup (GPU, MinIO, MySQL)
├── demo.sh                                # Live demo script (13 sections, skip support)
├── teardown.sh                            # Reset script (demo reset or full cluster reset)
├── manifests/
│   ├── dspa.yaml                          # Pipeline server (DSPA) + S3 credentials
│   ├── gpu-cluster-policy.yaml            # NVIDIA ClusterPolicy reference
│   ├── hardware-profile.yaml              # GPU toleration + resource identifiers
│   ├── minio.yaml                         # MinIO S3 storage
│   ├── model-registry-db.yaml             # MySQL backend for Model Registry
│   ├── model-registry-instance.yaml       # ModelRegistry CR instance
│   ├── serving-runtime.yaml               # Triton ServingRuntime (bare YAML)
│   ├── serving-runtime-template.yaml      # Triton as OpenShift Template
│   ├── llama-stack.yaml                   # LlamaStack server (bare deployment)
│   └── llama-stack-playground.yaml        # LlamaStack Playground (Streamlit UI)
└── notebooks/
    ├── gpu-check.py                       # Verify TensorFlow sees the GPU
    ├── gpu-demo.py                        # GPU matrix multiply benchmark
    ├── train-and-upload.py                # Train model + upload to MinIO
    ├── fsi-fraud-pipeline.ipynb           # KFP v2 pipeline (compiles to IR YAML)
    ├── validate-model.ipynb               # Validate step (standalone notebook)
    └── inference-test.ipynb               # Send predictions to deployed model
```

## Usage

### 1. Pre-demo setup

Run `setup.sh` the day before. It provisions GPU infrastructure (via `ocp-gpu-setup`), creates an OpenShift user, and deploys MinIO and MySQL:

```bash
./setup.sh
```

This script is idempotent -- safe to re-run if interrupted.

### 2. Live demo

Run `demo.sh` during the presentation. It uses [demo-magic](https://github.com/paxtonhare/demo-magic) for stepped execution -- press ENTER to advance each command:

```bash
./demo.sh
```

Each section can be skipped individually. Dependency checks warn if a previous section was skipped.

### 3. Teardown

Reset after the demo:

```bash
./teardown.sh          # Demo reset -- remove demo projects, keep infrastructure
./teardown.sh --full   # Full cluster reset -- remove everything (requires confirmation)
```

Demo reset removes `granite-demo`, `fsi-demo`, model registry, hardware profile, serving runtimes, and the RHOAI operator (so it can be re-installed live in Section 4). MinIO and MySQL data is cleared but the services are restarted fresh. GPU operators are preserved.

Full reset also removes MinIO, MySQL, GPU operators, and machinesets. Requires typing `FULL RESET` to confirm.

## Demo Sections

| # | Section | Story Beat | Method |
|---|---------|-----------|--------|
| 1 | Check Current State (NFD, GPU, taints) | "The GPU foundation" | CLI |
| 2 | Node Feature Discovery | | CLI |
| 3 | NVIDIA GPU Operator (ClusterPolicy, nvidia-smi) | | CLI |
| 4 | Install RHOAI | "The AI platform" | CLI + Browser |
| 5 | Hardware Profile (GPU toleration) | | CLI or Browser |
| 6 | Model Catalog — Deploy Granite LLM | "Foundation models, one click" | Browser |
| 7 | Serving Runtimes & Backing Services | "How models get served" | CLI + Browser |
| 8 | LlamaStack + Chat with Granite | "The wow moment" | Browser |
| 9 | Workbench & Train Custom Model | "Build your own model" | CLI + Browser |
| 10 | Model Registry | "Governance & lineage" | CLI + Browser |
| 11 | Deploy from Registry & Test Inference | "From registry to production" | Browser |
| 12 | Data Science Pipelines & Experiments | "Automate the lifecycle" | CLI + Browser |
| 13 | Closing | | CLI |

## Key Design Decisions

- **Value-first storytelling**: GenAI wow moment (Granite chat) comes before custom ML deep dive. Business stakeholders see value immediately.
- **RHOAI 3.0**: Uses Gateway API (not Routes) for Dashboard URL. Uses KServe (not ModelMesh).
- **Internal inference only**: No external routes for model endpoints. Inference runs from inside the cluster (workbench notebook).
- **Triton for custom ML, vLLM for LLMs**: Two serving runtimes for two use cases.
- **Model Registry workflow**: Train -> register in registry with metadata -> deploy from registry. Full lineage tracking.
- **MinIO for S3**: Stands in for production S3/Ceph/ODF. Bucket creation is done live during the demo.
- **Pipelines**: KFP v2 SDK compiles to IR YAML (Intermediate Representation). RHOAI 3.0 uses Argo Workflows backend. Pipeline is defined in a notebook (`fsi-fraud-pipeline.ipynb`) so the presenter can walk through each step with the audience.
- **LlamaStack**: Deployed as bare Deployments (not via operator or Helm). The operator's security context conflicts with the `eformat` images. Server (`distribution-remote-vllm:0.2.15`) and playground (`streamlit_client:0.2.15`) are from the same author, ensuring API compatibility.
- **GPU management**: Granite LLM is scaled to zero in Section 11 to free the GPU for the custom fraud model deployment. Two A10G GPUs are shared across the demo.
- **Pre-warming**: Optional setup.sh step caches serving runtime images on GPU nodes for faster demo deployments.
