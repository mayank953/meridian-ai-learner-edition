output "vector_search_index_id" {
  description = "Put this in .env as VECTOR_SEARCH_INDEX_ID"
  value       = google_vertex_ai_index.documents.id
}

output "vector_search_endpoint_id" {
  description = "Put this in .env as VECTOR_SEARCH_INDEX_ENDPOINT_ID"
  value       = google_vertex_ai_index_endpoint.documents.id
}

output "bucket_name" {
  description = "Put this in .env as GCS_BUCKET_NAME"
  value       = google_storage_bucket.staging.name
}

output "image_repository" {
  description = "Push your image to <this>/meridian-ai:latest"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "service_url" {
  description = "The public address of the app"
  value       = google_cloud_run_v2_service.app.uri
}
