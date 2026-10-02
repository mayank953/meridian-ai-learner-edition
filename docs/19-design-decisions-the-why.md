# 19 · Design decisions — the reasons behind each choice

This is the page to read when you think "why did they do it *this* way?" Each entry gives the choice, the reason, what you would lose if you chose differently, and where to see it in the code. Some choices are deliberate trade-offs for a learning project; those are marked **(learning trade-off)** so you know what a production system would change.

---

## A. Project structure

| Choice | Why | Cost / alternative | Where |
|---|---|---|---|
| Split the backend into `api`, `rag`, `agent`, `config`, `logger` | One job per package; changes stay local; easy to find things; testable parts | More files to open. A single file is fine for a 100-line experiment, not for a growing product | [04](04-project-tour.md) |
| `api/endpoints.py` contains only thin routes | A route's job is to translate HTTP into a function call and back. Logic in routes cannot be reused or tested without a web server | One extra function call | `api/endpoints.py` |
| `ingest_pdf()` is used by both upload and bucket-import | Same behaviour in both paths; fix a bug once | – | `rag/data_ingestion.py` |
| Frontend and backend in separate folders | Different languages, tools and build outputs | Two terminals while developing | `frontend/`, `backend/` |
| Prompts in their own file | They are text that is edited far more often than code, sometimes by non-programmers | Slightly more indirection | `agent/prompts.py` |
| Tests in `backend/tests/` with fake settings | Anyone can run them with no accounts and no cost | They test wiring, not the quality of AI answers | `backend/tests/` |

## B. Python and configuration

| Choice | Why | Where |
|---|---|---|
| Pinned versions in `requirements.txt` | AI libraries change fast and break each other. Pinning makes every learner's environment identical | `requirements.txt` |
| `requirements-dev.txt` separate | The server image should not carry test tools | `requirements-dev.txt` |
| Settings via environment variables / `.env` | Code stays the same everywhere; secrets stay out of Git | `config/settings.py` |
| One `Settings` object, created once | A single source of truth; typed and validated | `config/settings.py` |
| Models and connections created lazily with `lru_cache` | The server can start, and `/api/health` and the tests work, before any cloud is configured; each object is built once | `rag/llm.py`, `rag/embeddings.py`, `rag/vector_store.py` |
| `temperature = 0` by default | The same question gives (nearly) the same answer, which is easier to debug and to compare. Raise it for more varied wording | `LLM_TEMPERATURE` |
| Model name is a setting | Models are retired regularly. Changing one should not need a code change | `VERTEX_LLM_MODEL_NAME` |

## C. Documents and search (RAG)

| Choice | Why | Trade-off |
|---|---|---|
| Chunk size 1000 characters, overlap 100 | Large enough to hold a full idea, small enough that a search hit is precise. Overlap keeps ideas that straddle a boundary | Too small loses context; too large dilutes the match. Try it: [11](11-rag-pipeline.md) exercise |
| 768-dimension embeddings (`text-embedding-005`) | The index was created with 768 dimensions; every vector stored and every question must have the same length | Changing the model means a new index |
| Same embedding model for storing and searching | Vectors from different models are not comparable | – |
| Dot-product distance, tree-AH algorithm | Fast approximate search on Vertex AI; a standard choice for text embeddings | Approximate means it can very rarely miss the true best match |
| Streaming updates (`stream_update=True`) | New uploads become searchable within a short time | Costs more than batch updates |
| Retrieve 3 chunks (`k=3`) | Enough context for most questions without making the prompt long and costly | Questions needing many passages may be answered incompletely; use the *contextual* option (10 chunks) |
| Prompt says "answer only from the context; say you don't know" | Reduces made-up answers (hallucination) | The model may refuse when the answer is partly there |
| Upload also saves the PDF in Cloud Storage | The index holds chunks, not the originals; a copy lets you re-index later | Small storage cost |
| `create_retrieval_chain` from `langchain_classic` | Same behaviour as earlier LangChain versions, still supported | Online tutorials mix old and new imports (see [11](11-rag-pipeline.md)) |

## D. Agents

| Choice | Why | Trade-off |
|---|---|---|
| Three specialist agents instead of one | Each has a short, focused prompt and only the tools it needs. This is more reliable than one giant prompt | More model calls = slower and costlier |
| A supervisor in plain Python, then one summarising model call | Control flow you can read and debug. The order and the final decision rules are visible | Less flexible than a self-organising multi-agent graph |
| Agents run one after another | Easy to read and to follow in the logs | They could run in parallel for speed |
| Exact output formats in the prompts | The next step (and the CFO rules) depends on fixed words like `RED ALERT` | A format change must be made in two places |
| `create_agent` (LangChain) | The current standard way; runs on LangGraph underneath, so there is no graph code to maintain | For loops, branches, and human approval steps you would use LangGraph directly |
| Tools ask the model instead of calling real services **(learning trade-off)** | No external accounts are needed to run the demo | A real system must call real sanctions, credit and tax services and keep a human reviewer |
| Each tool catches its own errors and returns a "manual review required" message | One failed lookup should not crash the whole audit | Errors can be hidden inside the text; check the logs |
| The FX tool uses a real exchange-rate API first and the model only as a fallback | Facts that exist as data should come from data | Needs internet access |

## E. API design

| Choice | Why | Where |
|---|---|---|
| `/api/...` prefix | Separates API URLs from website pages on the same server | `api/endpoints.py` |
| Pydantic request/response models | Automatic validation, documentation, and clear errors | `api/schemas.py` |
| Routes return HTTP 500 with the real message | The frontend can show it and learners can debug | Production systems usually hide internals |
| CORS allows all origins **(learning trade-off)** | Frontend (port 3000) and backend (port 8080) are different origins in development | Restrict to your site in production |
| Upload runs the slow part in a thread | Keeps the server responsive | [09](09-fastapi-deep-dive.md) |
| `/api/status` reads settings and does not call the cloud | It must work even when the cloud is misconfigured, since that is when you need it | `api/endpoints.py` |
| The server also serves the React build | One container, one URL, no CORS problems in production | `api/main.py` |
| In-memory upload history **(learning trade-off)** | Simple. Resets when the server restarts | A database would persist it |

## F. Logging

| Choice | Why | Where |
|---|---|---|
| Structured JSON logs | Searchable and filterable by machines | `logger/custom_logger.py` |
| Both console and file | The console for live viewing, the file as a record | same |
| A `severity` field | Cloud Logging uses it to colour and filter | `add_severity` |
| One shared logger | One format everywhere | `logger/__init__.py` |
| Upload the log file at shutdown | The container's disk disappears | `main.py` lifespan |

## G. Packaging and cloud

| Choice | Why | Trade-off |
|---|---|---|
| Docker | Same environment everywhere, and Cloud Run runs containers | Learning Docker |
| Multi-stage Dockerfile | The final image has no Node.js or build tools | Slightly longer Dockerfile |
| Copy `requirements.txt` before the code | Docker caches layers; package installs are slow and rarely change | – |
| `.dockerignore` excludes `.env` and `credentials/` | Secrets must never be baked into an image anyone can pull | – |
| Cloud Run | No server to manage; scales to zero; pay for use | Cold starts |
| `--max-instances 3` | Caps cost and abuse because the URL is public | Heavy traffic is limited |
| `--allow-unauthenticated` **(learning trade-off)** | Anyone can open the demo without signing in | Put sign-in in front of real data |
| API key in Secret Manager | Keeps it out of code, images, and the console's plain environment-variable list | One more service |
| Secret access granted on that one secret | Least privilege: a compromised service can read only what it needs | – |
| Vector Search through a deployed endpoint | Managed, fast, fits LangChain | **Hourly cost while deployed** ([17](17-cleanup.md)) |
| A service-account JSON key for GitHub **(learning trade-off)** | Simplest to set up | Keys can leak. Production uses Workload Identity Federation ([20](20-alternatives-and-next-steps.md)) |
| `editor` + `projectIamAdmin` for the deployer **(learning trade-off)** | One robot can create everything | Far more access than necessary |
| Provisioning with `gcloud` in GitHub Actions rather than Terraform | No additional tool; one file does everything | See [15](15-provisioning-how-resources-are-created.md) |
| Region `us-central1` | Vertex AI features and quotas are broadly available there | Choose a region near your users and data-residency rules |

## H. Deliberate simplifications to remember

1. The audit "data sources" are the language model's memory, not databases.
2. The deployed app has no sign-in.
3. Broad permissions for the deployer.
4. No automatic tests in the GitHub workflow.
5. No database for history; no answer-quality evaluation.
6. Everything is a single Cloud Run service with a single region.

See [20](20-alternatives-and-next-steps.md) for the upgrade path for each.

## I. A way to read any unfamiliar file

Ask, in this order: **What is this file's one job? Who calls it? What does it call? What does it need from settings? What does it write to the log? What would break if I deleted it?** Every file in this project can be explained by those six answers.
