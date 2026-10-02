# Terraform (optional `infra/terraform/` example)

Terraform is **not** used by the main deployment (GitHub Actions + `gcloud`). These entries apply only if you try the example.

**`Error: Invalid provider configuration` / `No credentials`**
Cause: Terraform cannot find Google credentials. Fix: `gcloud auth application-default login`, then `terraform plan` again.

**`Error 403: ... API has not been used in project ... before or it is disabled`**
Cause: an API was not enabled yet when a resource was created. Fix: wait a minute and run `terraform apply` again (the first resources enable the APIs).

**`Error 409: ... already exists`**
Cause: the resource was already created, for example by the GitHub Actions workflow. Do not use both tools on one project. Fix: use a fresh project, or delete the existing resource, or import it (`terraform import`).

**`No value for required variable gemini_api_key`**
Fix: `export TF_VAR_gemini_api_key="your-key"` before running Terraform. Do not write the key into a committed file.

**Machine type / shard size rejected when deploying the index**
Cause: not every Vector Search machine type supports every shard size. Fix: check Google's Vector Search documentation and change `index_machine_type` / `index_shard_size`.

**Cloud Run shows Google's "hello" page**
Expected after the first apply. Build your image and re-apply with `-var "container_image=..."` (see doc 15).

**Concern: the API key is in the state file**
True. `terraform.tfstate` is git-ignored here. Never share or commit it; protect remote state in real projects.

**`terraform destroy` leaves the Vector Search deployment running**
Check the console: Vertex AI → Vector Search → Index endpoints. Undeploy and delete manually if needed ([cleanup](../../docs/17-cleanup.md)).
