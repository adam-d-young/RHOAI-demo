# RHOAI Demo - Get Started with OpenShift AI

Instructor-led demo for FSI Bootcamp Day 1. Covers GPU infrastructure, Red Hat OpenShift AI installation, model training, model registry, model serving, and data science pipelines.

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

Clone `ocp-gpu-setup` as a sibling directory:

```
your-workspace/
  ocp-gpu-setup/    # GPU infrastructure setup
  RHOAI-demo/       # This repo
```

### Tools

- `oc` CLI, logged into the target cluster
- `bat` (syntax-highlighted file viewer) -- `brew install bat`

## Repo Structure

```
RHOAI-demo/
├── demo-magic.sh                          # demo-magic library (typewriter effect)
├── setup.sh                               # Pre-demo cluster setup (GPU, MinIO, MySQL)
├── demo.sh                                # Live demo script (13 sections, skip support)
├── manifests/
│   ├── dspa.yaml                          # Pipeline server (DSPA) + S3 credentials
│   ├── gpu-cluster-policy.yaml            # NVIDIA ClusterPolicy reference
│   ├── hardware-profile.yaml              # GPU toleration + resource identifiers
│   ├── minio.yaml                         # MinIO S3 storage
│   ├── model-registry-db.yaml             # MySQL backend for Model Registry
│   ├── model-registry-instance.yaml       # ModelRegistry CR instance
│   ├── serving-runtime.yaml               # Triton ServingRuntime (bare YAML)
│   └── serving-runtime-template.yaml      # Triton as OpenShift Template
└── notebooks/
    ├── gpu-check.py                       # Verify TensorFlow sees the GPU
    ├── gpu-demo.py                        # GPU matrix multiply benchmark
    ├── train-and-upload.py                # Train model + upload to MinIO
    ├── fsi-fraud-pipeline.py              # KFP v2 pipeline (compiles to IR YAML)
    ├── validate-model.ipynb               # Validate step (added via Elyra)
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

## Demo Sections

| # | Section | Method |
|---|---------|--------|
| 1 | Check Current State (NFD, GPU, taints) | CLI |
| 2 | Node Feature Discovery | CLI |
| 3 | NVIDIA GPU Operator (ClusterPolicy, nvidia-smi) | CLI |
| 4 | Install RHOAI (OperatorHub, DataScienceCluster) | CLI + Browser |
| 5 | Hardware Profile (GPU toleration) | CLI or Browser |
| 6 | Pre-deployed Infrastructure (MinIO, MySQL) | CLI + Browser |
| 7 | GPU Serving Runtime (Triton) | CLI or Browser |
| 8 | Workbench & Train Model | Browser (JupyterLab) |
| 9 | Model Registry | CLI + Browser |
| 10 | Deploy from Model Registry | Browser |
| 11 | Test Inference | Browser (Jupyter notebook) |
| 12 | Data Science Pipelines & Experiments | CLI + Browser |
| 13 | Closing | CLI |

## Key Design Decisions

- **RHOAI 3.0**: Uses Gateway API (not Routes) for Dashboard URL. Uses KServe (not ModelMesh).
- **Internal inference only**: No external routes for model endpoints. Inference runs from inside the cluster (workbench notebook).
- **Triton Inference Server**: Serves TensorFlow SavedModel on GPU with auto-detected tensor names.
- **Model Registry workflow**: Train -> register in registry with metadata -> deploy from registry. Full lineage tracking.
- **MinIO for S3**: Stands in for production S3/Ceph/ODF. Bucket creation is done live during the demo.
- **Pipelines**: KFP v2 SDK compiles to IR YAML (Intermediate Representation). RHOAI 3.0 uses Argo Workflows backend. The pipeline is intentionally 4 steps; the validate step is added live using Elyra to show both code-first and visual pipeline building.
