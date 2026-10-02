# 15 · Provisioning — how the cloud resources get created

> **Short answer to a common question: this project provisions its cloud resources with GitHub Actions running `gcloud` commands (`.github/workflows/deploy.yml`). It does *not* use Terraform.** The folder `infra/terraform/` is an optional, equivalent way to do the same job, included for learning. Pick one approach per Google Cloud project.

---

## 1. What is "provisioning"?

Your code needs places to live and things to use: a storage bucket for PDFs, a vector database, a place to run the server, a locker for the API key. None of these exist in a new Google Cloud project. **Provisioning** means creating them (and the permissions that connect them). **Deployment** means putting a new version of your *code* onto them. This project's resources:

| Resource | What it is for |
|---|---|
| Enabled Google APIs | A service must be switched on in a project before you can use it |
| Cloud Storage bucket | PDFs, logs, index staging data |
| Vertex AI Vector Search index | Stores the vectors |
| Vertex AI Vector Search endpoint + deployed index | The running search service (billed by the hour) |
| Secret Manager secret | Holds the Gemini API key |
| Artifact Registry / image registry | Stores the Docker image |
| Cloud Run service | Runs the app |
| IAM permissions | Who may do what |

## 2. Three ways to create resources

| Way | How | Good | Bad |
|---|---|---|---|
| **A. Click in the console** | Web pages in console.cloud.google.com | Easiest to learn; nothing to install | Slow, error-prone, impossible to repeat exactly, undocumented |
| **B. Scripted commands** (what this project does) | A list of `gcloud` commands, run by a script or by GitHub Actions | Repeatable; the script *is* the documentation; no new tool | You must write "create only if it does not exist" logic yourself; no memory of what exists |
| **C. Infrastructure as Code with Terraform** | You *declare* what should exist; Terraform makes it so | Idempotent by design; shows a plan before changing; can destroy everything cleanly; tracks state | One more tool and language to learn; a state file to protect |

### Imperative vs declarative

- **Imperative** (way B): you write the *steps*. "Create a bucket. Then create an index…". If you run it twice, you must guard against creating things twice.
- **Declarative** (way C): you write the *end result*. "There is a bucket named X." Terraform compares this with reality and does only what is missing.

## 3. What this project does: GitHub Actions + `gcloud`

`deploy.yml` is a recipe that GitHub runs on a temporary computer. The provisioning steps use the same pattern again and again: **check, then create only if missing.** This makes the workflow safe to re-run. Example from the bucket step:

```bash
if ! gcloud storage buckets describe gs://PROJECT-vector-staging >/dev/null 2>&1; then
  gcloud storage buckets create gs://PROJECT-vector-staging --location=us-central1 \
    --uniform-bucket-level-access --public-access-prevention
else
  echo "Vector bucket already exists."
fi
```

`describe` succeeds if the bucket exists; `!` negates it; so the `create` only runs on the first deployment. The same idea is used for the index, the endpoint, the deployed index and the secret.

Full step list: [16 · GitHub Actions](16-cicd-github-actions.md).

### Pros and cons in this project

| Pro | Con |
|---|---|
| No extra tool: only `gcloud`, which you already install | No record of what was created. Deleting is done by hand ([17](17-cleanup.md)) |
| One file does provisioning **and** deployment | Long shell script with polling loops (`sleep 60`) to wait for slow operations |
| Easy to read top to bottom | Not safe against *drift* (someone changing resources in the console) |
| Re-runnable | Changing a setting on an existing resource needs extra code; the script only creates |

## 4. The optional Terraform version

Location: `infra/terraform/`. It declares the same resources. It is **not** used by the workflow and nothing in the application depends on it.

### 4.1 Terraform in ten minutes

| Concept | Meaning | Example here |
|---|---|---|
| **Provider** | A plugin that knows how to talk to a platform | `hashicorp/google` in `versions.tf` |
| **Resource** | One thing to create | `resource "google_storage_bucket" "staging" { ... }` |
| **Variable** | An input you can change | `variable "project_id"` in `variables.tf` |
| **Output** | A value printed after creation | `service_url` in `outputs.tf` |
| **Reference** | One resource using another's value | `google_storage_bucket.staging.name` |
| **Dependency graph** | Terraform works out the creation order from references | The Cloud Run service waits for the secret, because it references it |
| **`depends_on`** | An explicit ordering when there is no reference | APIs must be enabled before resources |
| **`for_each`** | Create one resource per item in a list | One `google_project_service` per API |
| **State** | A file recording what Terraform created | `terraform.tfstate` (**git-ignored; contains secrets**) |
| **Plan** | A preview of what would change | `terraform plan` |
| **Apply / Destroy** | Make it so / remove everything it created | `terraform apply`, `terraform destroy` |

The four commands:

```bash
terraform init      # download the provider (once)
terraform plan      # show what would be created, changed or deleted - changes nothing
terraform apply     # do it (asks you to type yes)
terraform destroy   # remove everything Terraform created
```

### 4.2 The files

| File | Contents |
|---|---|
| `versions.tf` | Required Terraform version, the Google provider, and its default project/region |
| `variables.tf` | Inputs: `project_id`, `region`, `gemini_api_key` (marked `sensitive`), `container_image`, model names, and the **cost-control knobs** `index_machine_type`, `index_replica_count`, `index_shard_size`, `cloud_run_max_instances` |
| `main.tf` | The resources (below) |
| `outputs.tf` | Prints the index ID, endpoint ID, bucket name, image repository and the service URL |
| `terraform.tfvars.example` | Template for your values |

Resources in `main.tf`, in the order they are declared:

| # | Resource | Equivalent step in `deploy.yml` |
|---|---|---|
| 1 | `google_project_service.apis` (one per API) | "Enable Required GCP APIs" |
| 2 | `google_storage_bucket.staging` + `google_storage_bucket_object.initial_embeddings` | "Ensure Storage Buckets Exist" + copying `init_embeddings.json` |
| 3 | `google_vertex_ai_index.documents` (768 dimensions, streaming updates) | `gcloud ai indexes create` |
| 4 | `google_vertex_ai_index_endpoint.documents` | `gcloud ai index-endpoints create` |
| 5 | `google_vertex_ai_index_endpoint_deployed_index.documents` | `gcloud ai index-endpoints deploy-index` |
| 6 | `google_secret_manager_secret` + `_version` | "Ensure Secret Manager Has API Key" |
| 7 | `google_artifact_registry_repository.images` | (the workflow uses `gcr.io` instead) |
| 8 | `google_service_account.app` + three `*_iam_member` grants | (the workflow uses the default compute account) |
| 9 | `google_cloud_run_v2_service.app` + `..._iam_member.public` | `gcloud run deploy` + public access |

### 4.3 Differences from the workflow (so you are not surprised)

| Topic | `deploy.yml` | Terraform example |
|---|---|---|
| Vector Search machine type | not set (Google's default applies) | `e2-standard-2`, **set by a variable** |
| Replicas | not set (Google's default is 2) | `1`, **set by a variable** |
| Index shard size | `SHARD_SIZE_MEDIUM` | `SHARD_SIZE_SMALL` (variable) |
| Image registry | `gcr.io/<project>/…` | Artifact Registry repository `meridian` |
| App identity | project's default compute service account | A dedicated `meridian-app` account with only three permissions (least privilege) |
| The Docker image | built by the workflow | **You build it** (steps below); Terraform first uses Google's public hello-world image |

### 4.4 How to run it

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars        # edit: project_id, region
export TF_VAR_gemini_api_key="your-key"             # keep the key out of files
gcloud auth application-default login               # Terraform uses these credentials

terraform init
terraform plan
terraform apply
```

The first `apply` creates everything and shows a placeholder web page at `service_url` (Google's sample container). Then build and publish **your** image and re-apply:

```bash
REGION=us-central1
REPO="$REGION-docker.pkg.dev/YOUR_PROJECT_ID/meridian"
gcloud builds submit --tag "$REPO/meridian-ai:latest" ../..          # builds the Dockerfile in the cloud
terraform apply -var "container_image=$REPO/meridian-ai:latest"
```

Copy the outputs `vector_search_index_id`, `vector_search_endpoint_id` and `bucket_name` into your `.env`. Remove everything with `terraform destroy` (the bucket is configured to delete even when it contains files; this is for learning only).

### 4.5 Honest limits of this example

- It passes `terraform fmt` and `terraform validate`, which check the *syntax and structure*. **It has not been applied to a real Google Cloud project by the author.** Treat it as a reference and expect to adjust it.
- Check Google's documentation on which Vector Search machine types fit which shard sizes before changing those variables; an invalid combination is rejected at apply time.
- Terraform's **state file records every value, including your API key**. It is git-ignored here. In a team you keep state in a protected remote location (for example a Cloud Storage bucket with versioning and tight access).
- **Do not run the GitHub workflow and Terraform against the same project.** Both create an index called `financial-docs-production`, an endpoint called `financial-docs-endpoint`, a secret `GOOGLE_API_KEY`, and a Cloud Run service `meridian-ai-cloud-run`; the second tool fails or conflicts.

## 5. Which should you use?

| Situation | Choice |
|---|---|
| Following this course | **GitHub Actions** (the default path in [06](06-google-cloud-setup.md)) |
| You want to understand infrastructure-as-code | Read `infra/terraform/` side by side with `deploy.yml`; try it in a throw-away project |
| A team product that must be reproducible, reviewed and audited | Terraform (or a similar tool) for infrastructure, with GitHub Actions only to run it and to deploy code |

## 6. Exercises

1. In `deploy.yml`, find the three `if`/`else` blocks that make the Vector Search step re-runnable.
2. In `main.tf`, find where Cloud Run gets the API key and explain why the key is not written in the file.
3. Run `terraform init && terraform validate` in `infra/terraform/` (no cloud account needed for `validate`).
4. Run `terraform plan` in a throw-away project and read what would be created. What would you not want to leave running overnight?
