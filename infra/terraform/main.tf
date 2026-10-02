# ---------------------------------------------------------------------------
# This file creates the same things as .github/workflows/deploy.yml,
# but as DECLARED resources instead of a script of gcloud commands.
# Read docs/18-provisioning-and-terraform.md first.
# ---------------------------------------------------------------------------

locals {
  # APIs that must be switched on before the resources below can be created.
  apis = [
    "aiplatform.googleapis.com",       # Vertex AI: embeddings + Vector Search
    "run.googleapis.com",              # Cloud Run
    "secretmanager.googleapis.com",    # Secret Manager
    "storage.googleapis.com",          # Cloud Storage
    "artifactregistry.googleapis.com", # Docker image storage
    "cloudbuild.googleapis.com",       # Builds images in the cloud
    "logging.googleapis.com",          # Cloud Logging
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]

  bucket_name = "${var.project_id}-vector-staging"
}

# 1) Enable the APIs ---------------------------------------------------------
resource "google_project_service" "apis" {
  for_each = toset(local.apis)

  service            = each.value
  disable_on_destroy = false # don't switch APIs off when you run "terraform destroy"
}

# 2) Cloud Storage bucket: uploaded PDFs, logs, and index staging data --------
resource "google_storage_bucket" "staging" {
  name                        = local.bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # lets "terraform destroy" delete a non-empty bucket (learning only)

  depends_on = [google_project_service.apis]
}

# The index needs at least one starting vector. This file holds a single random one.
resource "google_storage_bucket_object" "initial_embeddings" {
  name   = "index-data/init_embeddings.json"
  bucket = google_storage_bucket.staging.name
  source = "${path.module}/../../init_embeddings.json"
}

# 3) Vertex AI Vector Search: index, endpoint, and deployment ------------------
resource "google_vertex_ai_index" "documents" {
  display_name        = "financial-docs-production"
  region              = var.region
  index_update_method = "STREAM_UPDATE"

  metadata {
    contents_delta_uri = "gs://${google_storage_bucket.staging.name}/index-data"

    config {
      dimensions                  = 768 # must match the embedding model
      approximate_neighbors_count = 150
      distance_measure_type       = "DOT_PRODUCT_DISTANCE"
      shard_size                  = var.index_shard_size

      algorithm_config {
        tree_ah_config {
          leaf_node_embedding_count    = 1000
          leaf_nodes_to_search_percent = 10
        }
      }
    }
  }

  depends_on = [google_storage_bucket_object.initial_embeddings]
}

resource "google_vertex_ai_index_endpoint" "documents" {
  display_name            = "financial-docs-endpoint"
  region                  = var.region
  public_endpoint_enabled = true

  depends_on = [google_project_service.apis]
}

# Deploying the index to the endpoint is what starts the hourly billing.
resource "google_vertex_ai_index_endpoint_deployed_index" "documents" {
  index_endpoint    = google_vertex_ai_index_endpoint.documents.id
  index             = google_vertex_ai_index.documents.id
  deployed_index_id = "deployed_financial_docs"
  display_name      = "financial-docs-deployed"

  dedicated_resources {
    machine_spec {
      machine_type = var.index_machine_type
    }
    min_replica_count = var.index_replica_count
    max_replica_count = var.index_replica_count
  }
}

# 4) Secret Manager: the Gemini API key --------------------------------------
resource "google_secret_manager_secret" "gemini_key" {
  secret_id = "GOOGLE_API_KEY"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "gemini_key" {
  secret      = google_secret_manager_secret.gemini_key.id
  secret_data = var.gemini_api_key
}

# 5) Docker image repository ---------------------------------------------------
resource "google_artifact_registry_repository" "images" {
  repository_id = "meridian"
  location      = var.region
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}

# 6) A dedicated identity for the running app (least privilege) -----------------
resource "google_service_account" "app" {
  account_id   = "meridian-app"
  display_name = "Meridian AI Cloud Run service"

  depends_on = [google_project_service.apis]
}

# Use Vertex AI (embeddings + Vector Search queries and updates)
resource "google_project_iam_member" "app_vertex" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.app.email}"
}

# Read and write files, but only in our own bucket
resource "google_storage_bucket_iam_member" "app_bucket" {
  bucket = google_storage_bucket.staging.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.app.email}"
}

# Read only this one secret
resource "google_secret_manager_secret_iam_member" "app_secret" {
  secret_id = google_secret_manager_secret.gemini_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app.email}"
}

# 7) Cloud Run service ----------------------------------------------------------
resource "google_cloud_run_v2_service" "app" {
  name                = "meridian-ai-cloud-run"
  location            = var.region
  deletion_protection = false # allows "terraform destroy" (learning only)

  template {
    service_account = google_service_account.app.email

    scaling {
      min_instance_count = 0
      max_instance_count = var.cloud_run_max_instances
    }

    containers {
      image = var.container_image

      ports {
        container_port = 8080
      }

      env {
        name  = "ENVIRONMENT"
        value = "production"
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GCP_REGION"
        value = var.region
      }
      env {
        name  = "GCS_BUCKET_NAME"
        value = google_storage_bucket.staging.name
      }
      env {
        name  = "GCS_PREFIX"
        value = "uploads/"
      }
      env {
        name  = "VERTEX_LLM_MODEL_NAME"
        value = var.llm_model_name
      }
      env {
        name  = "VERTEX_EMBEDDING_MODEL_NAME"
        value = var.embedding_model_name
      }
      env {
        name  = "VECTOR_SEARCH_INDEX_ID"
        value = google_vertex_ai_index.documents.id
      }
      env {
        name  = "VECTOR_SEARCH_INDEX_ENDPOINT_ID"
        value = google_vertex_ai_index_endpoint.documents.id
      }
      # The key comes from Secret Manager, not from the config file.
      env {
        name = "GOOGLE_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.gemini_key.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_version.gemini_key,
    google_secret_manager_secret_iam_member.app_secret,
  ]
}

# Make the service public (anyone with the URL can open it).
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.app.name
  location = google_cloud_run_v2_service.app.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
