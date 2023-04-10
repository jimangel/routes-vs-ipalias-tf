# routes-vs-ipalias-tf

A MVP demo creating 2 GKE standard clusters (one routes based and one VPC native)

High-level networking summary:

- VPC `routes-migration-vpc`
  - auto_create_subnetworks: `false`
- Subnets (assume routable, non-overlapping):
  - name: `native-gke-subnetwork`
    - range: `10.0.1.0/24` (Node IPs)
    - secondaryIPs: `10.148.0.0/20` (Service IPs)
    - secondaryIPs: `10.144.0.0/14` (Pod IPs)
  - name: `routes-gke-subnetwork`
    - range: `10.0.0.0/24` (Node IPs)
- `routes-based` cluster ranges (assume NON GCP routable, defaults)
  - PodIPs: `10.244.0.0/14`
  - ServiceIPs: `10.247.240.0/20`

Assumes using a named `gcloud` configuration:

```
# CHECK / LIST CONFIGS:
gcloud config configurations list
gcloud config configurations activate <CONFIG_NAME>

# CREATE A CONFIG
gcloud config configurations create <CONFIG_NAME>
gcloud config set project <PROJECT_NAME>
gcloud config set account <ACCOUNT_NAME>
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-a
```

Export variables:

```
export CLOUDSDK_ACTIVE_CONFIG_NAME=my-cool-config
export TF_VAR_gcp_project=$(gcloud config list --format 'value(core.project)' 2>/dev/null)
export CLUSTER_NAME="cluster-routes"
export CLUSTER_NAME_2="cluster-vpc-native"
```

Apply infra:

```
git clone git@github.com:jimangel/routes-vs-ipalias-tf.git
cd routes-vs-ipalias-tf
terraform init
terraform plan
terraform apply
```