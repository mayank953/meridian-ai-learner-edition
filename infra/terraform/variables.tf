variable "project_id" {
  description = "Your Google Cloud project ID (not the display name)."
  type        = string
}

variable "region" {
  description = "Region for all resources. Vector Search, Cloud Run and the bucket should share it."
  type        = string
  default     = "us-central1"
}

variable "gemini_api_key" {
  description = "Gemini API key from Google AI Studio. Stored in Secret Manager. NOTE: it is also written to the Terraform state file."
  type        = string
  sensitive   = true
}

variable "container_image" {
  description = "Image for Cloud Run. The default is Google's public hello-world image so the first 'apply' works before you have built your own."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "llm_model_name" {
  description = "Gemini chat model used by the app."
  type        = string
  default     = "gemini-3.8-flash"
}

variable "embedding_model_name" {
  description = "Embedding model. Must produce 768 numbers to match the index."
  type        = string
  default     = "text-embedding-005"
}

# ---- Vector Search sizing (this is where most of the cost comes from) ----

variable "index_shard_size" {
  description = "SHARD_SIZE_SMALL / SHARD_SIZE_MEDIUM / SHARD_SIZE_LARGE. Check Google's docs for which machine types a shard size supports before changing."
  type        = string
  default     = "SHARD_SIZE_SMALL"
}

variable "index_machine_type" {
  description = "Machine type for each Vector Search serving node. Larger machines cost more per hour."
  type        = string
  default     = "e2-standard-2"
}

variable "index_replica_count" {
  description = "Number of serving replicas. Each replica is billed per hour while deployed. Google's SLA needs 2 or more; 1 is fine for learning."
  type        = number
  default     = 1
}

variable "cloud_run_max_instances" {
  description = "Upper limit on Cloud Run copies. Protects you from cost spikes."
  type        = number
  default     = 3
}
