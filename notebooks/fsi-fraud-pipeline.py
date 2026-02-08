"""
FSI Fraud Detection Training Pipeline (KFP v2)

4-step pipeline (intentionally missing the Validate step):
  1. Data Processing   - Generate synthetic transaction data
  2. Feature Extract   - Normalize and derive model features
  3. Train Model       - Fit a GradientBoosting classifier
  4. Upload Model      - Push artifacts to MinIO S3

The Validate step is provided separately (validate-model.ipynb) and
added visually using the Elyra pipeline editor during the demo.

Usage (run in workbench terminal):
  pip install kfp
  python fsi-fraud-pipeline.py

  Then import the generated YAML:
  RHOAI Dashboard -> Pipelines -> Import pipeline -> fsi-fraud-pipeline.yaml
"""

from kfp import dsl, compiler

# Internal OpenShift Python image -- available on all OCP clusters
BASE_IMAGE = "image-registry.openshift-image-registry.svc:5000/openshift/python:latest"


@dsl.component(
    base_image=BASE_IMAGE,
    packages_to_install=["numpy==1.26.4", "pandas==2.2.2"],
)
def data_processing(num_samples: int, dataset: dsl.Output[dsl.Dataset]):
    """Generate synthetic transaction data with fraud labels."""
    import numpy as np
    import pandas as pd
    import os

    np.random.seed(42)
    n = num_samples

    data = pd.DataFrame({
        "amount": np.random.exponential(500, n),
        "category": np.random.randint(0, 10, n),
        "time_delta": np.random.exponential(3600, n),
        "account_age_days": np.random.randint(1, 3650, n),
        "tx_frequency_7d": np.random.poisson(5, n),
    })

    # Fraud label: high amount + new account + high frequency -> more likely
    fraud_score = (
        (data["amount"] > 1000).astype(float) * 0.3
        + (data["account_age_days"] < 90).astype(float) * 0.3
        + (data["tx_frequency_7d"] > 10).astype(float) * 0.2
        + np.random.uniform(0, 0.2, n)
    )
    data["is_fraud"] = (fraud_score > 0.5).astype(int)

    os.makedirs(dataset.path, exist_ok=True)
    data.to_csv(f"{dataset.path}/transactions.csv", index=False)

    fraud_count = data["is_fraud"].sum()
    print(f"Generated {n} transactions ({fraud_count} fraud, {n - fraud_count} legit)")


@dsl.component(
    base_image=BASE_IMAGE,
    packages_to_install=["numpy==1.26.4", "pandas==2.2.2"],
)
def feature_extract(dataset: dsl.Input[dsl.Dataset], features: dsl.Output[dsl.Dataset]):
    """Normalize features to 0-1 range for model training."""
    import pandas as pd
    import os

    data = pd.read_csv(f"{dataset.path}/transactions.csv")

    feature_cols = ["amount", "category", "time_delta", "account_age_days", "tx_frequency_7d"]
    for col in feature_cols:
        min_val, max_val = data[col].min(), data[col].max()
        data[f"{col}_norm"] = (data[col] - min_val) / (max_val - min_val + 1e-8)

    norm_cols = [f"{c}_norm" for c in feature_cols]
    result = data[norm_cols + ["is_fraud"]]

    os.makedirs(features.path, exist_ok=True)
    result.to_csv(f"{features.path}/features.csv", index=False)

    print(f"Extracted {len(norm_cols)} normalized features from {len(result)} samples")


@dsl.component(
    base_image=BASE_IMAGE,
    packages_to_install=["numpy==1.26.4", "pandas==2.2.2", "scikit-learn==1.5.0"],
)
def train_model(features: dsl.Input[dsl.Dataset], model: dsl.Output[dsl.Model]):
    """Train a GradientBoosting fraud classifier."""
    import numpy as np
    import pandas as pd
    import pickle
    import os
    from sklearn.ensemble import GradientBoostingClassifier
    from sklearn.model_selection import train_test_split

    data = pd.read_csv(f"{features.path}/features.csv")
    feature_cols = [c for c in data.columns if c != "is_fraud"]

    X = data[feature_cols].values
    y = data["is_fraud"].values

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )

    clf = GradientBoostingClassifier(n_estimators=100, max_depth=3, random_state=42)
    clf.fit(X_train, y_train)

    os.makedirs(model.path, exist_ok=True)
    with open(f"{model.path}/model.pkl", "wb") as f:
        pickle.dump(clf, f)
    np.savez(f"{model.path}/test_data.npz", X_test=X_test, y_test=y_test)

    print(f"Train accuracy: {clf.score(X_train, y_train):.4f}")
    print(f"Test accuracy:  {clf.score(X_test, y_test):.4f}")


@dsl.component(
    base_image=BASE_IMAGE,
    packages_to_install=["boto3==1.34.0"],
)
def upload_model(model: dsl.Input[dsl.Model]):
    """Upload model artifacts to MinIO S3."""
    import os
    import boto3
    from botocore.client import Config

    s3 = boto3.client(
        "s3",
        endpoint_url="http://minio-service.default.svc.cluster.local:9000",
        aws_access_key_id="minio",
        aws_secret_access_key="minio123",
        config=Config(signature_version="s3v4"),
    )

    bucket = "models"
    prefix = "pipeline-output"

    for dirpath, _, filenames in os.walk(model.path):
        for filename in filenames:
            local_path = os.path.join(dirpath, filename)
            relative = os.path.relpath(local_path, model.path)
            s3_key = f"{prefix}/{relative}"
            print(f"Uploading: s3://{bucket}/{s3_key}")
            s3.upload_file(local_path, bucket, s3_key)

    print(f"\nModel uploaded to s3://{bucket}/{prefix}/")


@dsl.pipeline(name="FSI Fraud Detection Training")
def fsi_fraud_pipeline(num_samples: int = 10000):
    """Fraud detection training pipeline (validate step added via Elyra)."""
    data_task = data_processing(num_samples=num_samples)
    feature_task = feature_extract(dataset=data_task.outputs["dataset"])
    train_task = train_model(features=feature_task.outputs["features"])
    upload_model(model=train_task.outputs["model"])


if __name__ == "__main__":
    output_file = "fsi-fraud-pipeline.yaml"
    compiler.Compiler().compile(fsi_fraud_pipeline, output_file)
    print(f"Pipeline compiled to: {output_file}")
    print("Import via: RHOAI Dashboard -> Pipelines -> Import pipeline")
