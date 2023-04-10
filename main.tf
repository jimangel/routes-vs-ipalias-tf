# set with `export TF_VAR_gcp_project=""`
variable "gcp_project" {}

provider "google" {
  project = var.gcp_project
}

# Enable Google Kubernetes Engine API
resource "google_project_service" "gke" {
  service = "container.googleapis.com"
}

# Create new VPC
resource "google_compute_network" "vpc_network" {
  name                    = "routes-migration-vpc"
  auto_create_subnetworks = false
}

# Create subnet for routes based cluster
# Each node gets a /24 for a routes based cluster, since we only have a single node, I'm only using a /24
resource "google_compute_subnetwork" "routes_vpc_subnetwork" {
  name          = "routes-gke-subnetwork"
  network       = google_compute_network.vpc_network.self_link
  ip_cidr_range = "10.0.0.0/24"
  region        = "us-central1"
}

# Create a node service_account
resource "google_service_account" "node_sa" {
  account_id   = "kubernetes-engine-node-sa"
  display_name = "GKE Node Service Account"
}

# Assign bare minimum IAM
resource "google_project_iam_member" "metric_writer" {
  project = var.gcp_project
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node_sa.email}"
}
resource "google_project_iam_member" "viewer" {
  project = var.gcp_project
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.node_sa.email}"
}
resource "google_project_iam_member" "log_writer" {
  project = var.gcp_project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node_sa.email}"
}

# Let my node service account read the projects artifactory by default (easy image publishing)
resource "google_project_iam_member" "artifactory_read" {
  project = var.gcp_project
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.node_sa.email}"
}


######################################################################################
# First GKE using routes
######################################################################################
resource "google_container_cluster" "routes_based_cluster" {
  name               = "routes-based-cluster"
  location           = "us-central1-a"
  remove_default_node_pool = true
  initial_node_count       = 1

  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.gcp_project}.svc.id.goog"
  }

  # node network
  network = google_compute_network.vpc_network.self_link
  subnetwork = google_compute_subnetwork.routes_vpc_subnetwork.self_link
  networking_mode = "ROUTES"

  # shorten the timeouts
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  # trying to match close-ish to existing config
  addons_config {
    dns_cache_config {
      enabled = true
    }
  }
}

# add nodes to the cluster
resource "google_container_node_pool" "primary_nodes" {
  name       = "test-pool"
  cluster    = google_container_cluster.routes_based_cluster.id
  node_count = 3

  node_config {
    # preemptible  = true
    machine_type = "e2-standard-2"

    # Scopes that are used by NAP and GKE Autopilot when creating node pools. Use the "https://www.googleapis.com/auth/cloud-platform" scope to grant access to all APIs. It is recommended that you set service_account to a non-default service account and grant IAM roles to that service account for only the resources that it needs.
    service_account = google_service_account.node_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# Output
output "routes-cluster" {
  value = google_container_cluster.routes_based_cluster.name
}


######################################################################################
# Second GKE using VPC-native (ip-alias)
######################################################################################

# This is the cluster's node Internal IP(s)
resource "google_compute_subnetwork" "native_vpc_subnetwork" {
  name          = "native-gke-subnetwork"
  network       = google_compute_network.vpc_network.self_link
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-central1"
}

# taking the default subnet / network creation...
resource "google_container_cluster" "vpc_cluster" {
  name               = "vpc-cluster"
  location           = "us-central1"
  remove_default_node_pool = true
  initial_node_count       = 1

  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.gcp_project}.svc.id.goog"
  }

  # node network (let subnets be auto-created)
  network = google_compute_network.vpc_network.self_link
  subnetwork = google_compute_subnetwork.native_vpc_subnetwork.self_link

 ip_allocation_policy {
    # pod IP addresses (auto-picked /14 - 262,144 IP addresses for Pods.)
    cluster_ipv4_cidr_block  = "/14"
    # used for ClusterIP services (auto-picked /20 - 4,096 IP addresses)
    services_ipv4_cidr_block = "/20"
  }

  # I don't think this is required with the ip_allocation_policy above...
  networking_mode = "VPC_NATIVE"

  # shorten the timeouts
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  # trying to match close-ish to existing config
  addons_config {
    dns_cache_config {
      enabled = true
    }
  }
}

# add nodes to the cluster
resource "google_container_node_pool" "native_primary_nodes" {
  name       = "test-pool"
  cluster    = google_container_cluster.vpc_cluster.id
  node_count = 3

  node_config {
    # preemptible  = true
    machine_type = "e2-standard-2"

    # Scopes that are used by NAP and GKE Autopilot when creating node pools. Use the "https://www.googleapis.com/auth/cloud-platform" scope to grant access to all APIs. It is recommended that you set service_account to a non-default service account and grant IAM roles to that service account for only the resources that it needs.
    service_account = google_service_account.node_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# Output
output "vpc-cluster" {
  value = google_container_cluster.vpc_cluster.name
}