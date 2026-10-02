# 04 · Project tour — every folder and file, and why it is organised this way

Open the repository in your editor and keep this page beside it. Every file is listed. Terms like *package*, `.env` or *Dockerfile* are explained in [03 · Project basics](03-project-basics.md).

---

## 1. The whole repository at a glance

```
meridian-ai-learner-edition/
│
├── backend/                  PYTHON: the server (API, document search, agents)
├── frontend/                 TYPESCRIPT/REACT: the screens in the browser
│
├── Dockerfile                Recipe that packages frontend + backend into one image
├── .dockerignore             Files that must NOT go into that image
├── .github/workflows/        GitHub Actions: the automated deployment
├── infra/terraform/          OPTIONAL: the same cloud resources written for Terraform
│
├── requirements.txt          Python packages the app needs (exact versions)
├── requirements-dev.txt      + packages for tests and the sample-PDF generator
├── .env.example              Template for your private settings file
├── .gitignore                Files Git must not track
│
├── generate_json.py          Creates the one starter vector the index needs
├── init_embeddings.json      Output of generate_json.py (committed example)
├── index_metadata.json       Example of the index settings (the workflow writes its own)
│
├── Supporting Documents/     The architecture diagram image
├── docs/                     This learner guide (+ runnable examples)
├── course/                   Instructor material + the four sample PDFs
└── README.md                 The front door: what the project is and where to start
```

### Is Terraform used? Or GitHub Actions?

**GitHub Actions is what this project uses.** The file `.github/workflows/deploy.yml` creates the cloud resources by running `gcloud` commands, then builds and deploys the app. **Terraform is not part of the deployment.** The `infra/terraform/` folder is an *optional, alternative* way of creating the same resources, included so you can learn the technique. You never need it to run the project. Do not use both on the same Google Cloud project (they would try to create the same resources). The full explanation is in [15 · Provisioning](15-provisioning-how-resources-are-created.md).

---

## 2. Why the project is divided this way

There are three separate ideas behind the layout.

### 2.1 Divide by *responsibility*, not by size

Each folder answers one question. When something breaks, the error tells you which question to ask, and therefore which folder to open.

| Folder | Question it answers |
|---|---|
| `backend/api/` | How does the outside world talk to the server? |
| `backend/rag/` | How do we find the right passages in documents and answer from them? |
| `backend/agent/` | How do the AI agents check a purchase request? |
| `backend/config/` | Where do settings come from? |
| `backend/logger/` | How does the program write its diary? |
| `frontend/` | What does the user see and click? |

A single large file would mix all of these. A change to the tax prompt would sit a few lines from the code that opens PDFs, and a mistake in one could break the other. In separate files a change stays local. This is the *single responsibility* principle: **one file, one job**.

### 2.2 Divide by *how often and why it changes*

| Changes often, by developers | Changes per environment | Changes rarely |
|---|---|---|
| Code in `backend/`, `frontend/src/` | `.env`, GitHub secrets, Cloud Run settings | `Dockerfile`, `deploy.yml`, `tsconfig*.json` |

Keeping code, settings and infrastructure in different places means you can change a model name without touching code, and redeploy infrastructure without touching the application.

### 2.3 Divide so that dependencies point one way

```
api  ──►  rag, agent  ──►  config, logger
```

`api` may use `rag` and `agent`. `rag` and `agent` may use `config` and `logger`. Never the other way. `rag` knows nothing about web addresses; `config` knows nothing about documents. This keeps code testable (you can test `rag` without starting a web server) and prevents circular imports. The diagram and rules are in [05](05-architecture-and-flows.md).

---

## 3. `backend/` — the Python server

Run from the project root as `uvicorn api.main:app --app-dir backend`. The `--app-dir backend` option makes `backend/` the place Python searches for packages, which is why code writes `from rag.llm import get_llm` and not `from backend.rag.llm import get_llm`.

Each package folder contains an `__init__.py`. That empty-or-tiny file tells Python "this folder is a package".

### 3.1 `backend/api/` — the web layer

| File | What it does | Key contents |
|---|---|---|
| `main.py` | Creates the web application and wires everything together | the `FastAPI` app, CORS middleware, the four routers, a `lifespan` function that uploads logs on shutdown, and static-file serving for the built React app |
| `endpoints.py` | Defines every URL | `health`, `system_status`, `run_audit`, `rag_query`, `upload_documents`, `list_uploads`, `trigger_gcs_ingestion`; `get_supervisor()` builds the audit supervisor on first use |
| `schemas.py` | Describes the data in and out | `AuditRequest`, `AuditResponse`, `QueryRequest`, `QueryResponse` (Pydantic classes) |
| `__init__.py` | Marks the folder as a package | – |

Why three files? `schemas.py` is *what the data looks like*, `endpoints.py` is *what happens at each URL*, `main.py` is *how the app is assembled*. Deep dives: [08](08-backend-api.md), [09](09-fastapi-deep-dive.md).

### 3.2 `backend/rag/` — document question answering

| File | What it does | Key contents |
|---|---|---|
| `llm.py` | Gives the rest of the code the Gemini chat model | `get_llm()`, `extract_text()` |
| `embeddings.py` | Gives the code the text-to-numbers model | `get_embeddings()` |
| `vector_store.py` | Connects to the vector database | `get_vector_store()` |
| `data_ingestion.py` | Gets documents *into* the database | `split_into_chunks()`, `ingest_pdf()`, `ingest_data_from_gcs()`, `CHUNK_SIZE`, `CHUNK_OVERLAP` |
| `retrieval.py` | Gets answers *out* | `build_retriever()`, `ask_question()`, `SYSTEM_PROMPT` |

Why five files? Each is one external thing or one step: the chat model, the embedding model, the database, putting data in, taking answers out. If you replace Gemini with another model you edit only `llm.py`. If you replace Vertex Vector Search you edit `vector_store.py`. Deep dive: [11](11-rag-pipeline.md).

### 3.3 `backend/agent/` — the audit agents

| File | What it does | Key contents |
|---|---|---|
| `tools.py` | The five functions an agent may call | `check_sanctions_list`, `get_vendor_credit_score`, `calculate_cross_border_tax`, `validate_fx_hedge`, `categorize_expense` |
| `prompts.py` | The written instructions for each agent | `RISK_AGENT_PROMPT`, `TAX_AGENT_PROMPT`, `CONTROL_AGENT_PROMPT`, `SYNTHESIS_PROMPT_TEMPLATE` |
| `agents.py` | Builds the agents and runs them in order | `create_specialized_agent()`, `ProcurementSupervisor.run_audit()` |

Why three files? **Tools** (what an agent can *do*), **prompts** (what an agent is *told*) and **orchestration** (the *order* things happen) are three different decisions that change for different reasons. Prompt wording is edited constantly; orchestration rarely. Deep dive: [12](12-agents.md).

### 3.4 `backend/config/` and `backend/logger/`

| File | What it does |
|---|---|
| `config/settings.py` | One `Settings` class that reads every setting from environment variables / `.env` and provides a ready object `settings`. No other file reads `.env`. |
| `logger/custom_logger.py` | Builds the logger: JSON lines to the console and a file, adds a `severity` field, uploads the file to Cloud Storage when the server stops. |
| `logger/__init__.py` | Creates one shared logger, `GLOBAL_LOGGER`, which every module imports as `log`. |

Why separate? Almost every other file needs settings and logging. Putting them at the bottom of the dependency chart means everything can use them and they depend on nothing. Deep dive: [10](10-configuration-and-logging.md).

### 3.5 `backend/tests/` — automated checks

| File | What it does |
|---|---|
| `conftest.py` | Runs before the tests: sets fake settings so no cloud account is needed |
| `test_api.py` | Nine tests: health, status, unknown URL, question route, audit route, non-PDF rejection, chunking, sample PDFs, log severity |

Run with `pytest backend/tests`. Tests replace the AI and the cloud with simple stand-ins ("stubs"), so they are fast, free and repeatable.

---

## 4. `frontend/` — the browser application

Built with **React** (a library for building screens from components), **TypeScript** (JavaScript with types), **Vite** (a build tool and development server), **Tailwind CSS** (styling through short class names) and **shadcn/ui** (ready-made accessible components). The project was originally generated with a tool that created the setup files below. You only need to understand a small part of it.

### 4.1 Files you should read

| File | What it does |
|---|---|
| `src/lib/api.ts` | **The one place that calls the backend.** One function per URL |
| `src/pages/Index.tsx` | The page layout: sidebar plus the four tabs (RAG Q&A, Procurement Audit, Index Documents, System Status) |
| `src/components/DocumentUploadTab.tsx` | The *Index Documents* screen: choose PDFs, upload, see results, import from the bucket |
| `src/components/RagQATab.tsx` | The *RAG Q&A* screen: question box, retrieval-strategy choice, answer history |
| `src/components/AuditTab.tsx` | The *Procurement Audit* screen: request text, progress, the three reports and the memo |
| `src/components/SystemStatusTab.tsx` | The *System Status* screen: shows `/api/status` |

### 4.2 Files that make the frontend work (you rarely edit these)

| File | Purpose |
|---|---|
| `index.html` | The single HTML page. React fills in `<div id="root">` |
| `src/main.tsx` | Starts React and puts `App` on the page |
| `src/App.tsx` | Sets up page routing and shared providers; shows `Index` at `/`, `NotFound` otherwise |
| `src/pages/NotFound.tsx` | The "page not found" screen |
| `src/components/NavLink.tsx` | A small link helper |
| `src/components/ui/` | 49 generated shadcn/ui building blocks (buttons, cards, tabs…). **Do not edit by hand**; they come from the `shadcn` tool |
| `src/hooks/` | Small reusable React helpers (`use-toast`, `use-mobile`) |
| `src/lib/utils.ts` | The `cn()` helper that combines CSS class names |
| `src/index.css`, `src/App.css` | Global styles and colour variables |
| `src/vite-env.d.ts` | Type declarations for Vite |

### 4.3 Configuration files (tooling settings)

| File | Purpose |
|---|---|
| `package.json` | The frontend's `requirements.txt`: dependencies and the commands `npm run dev`, `build`, `lint`, `test` |
| `package-lock.json` | Exact versions installed. **Used by Docker** (`npm ci`) |
| `bun.lock` | A second lock file from the Bun package manager. Unused by this project's Docker build; npm is the supported tool |
| `vite.config.ts` | Dev server port **3000**, the `@` shortcut for `src/`, React plugin |
| `tsconfig.json`, `tsconfig.app.json`, `tsconfig.node.json` | TypeScript compiler rules (app code vs tool code) |
| `tailwind.config.ts`, `postcss.config.js` | Styling system settings |
| `components.json` | Settings for the shadcn/ui generator |
| `eslint.config.js` | Code-style checks (`npm run lint`) |
| `vitest.config.ts`, `src/test/setup.ts`, `src/test/example.test.ts` | Frontend unit-test setup; the only test is a placeholder |
| `playwright.config.ts`, `playwright-fixture.ts` | Browser end-to-end test setup (not used by the course) |

Why a separate folder? The frontend has its own language, package manager (`npm`), tools and build output (`frontend/dist/`). Keeping it in its own folder means `pip` and `npm` never touch each other's files.

---

## 5. Root files

| File | What it does | Why it is at the root |
|---|---|---|
| `README.md` | Introduction and links | The first thing GitHub shows |
| `requirements.txt` | Pinned Python dependencies | `pip install -r requirements.txt` and Docker both look here |
| `requirements-dev.txt` | `-r requirements.txt` plus `pytest`, `httpx`, `reportlab` | Tools learners need but production does not |
| `.env.example` | Template listing every setting | Copy to `.env` |
| `.gitignore` | Stops secrets and generated files entering Git | Applies to the whole repository |
| `.dockerignore` | Keeps `.env`, `credentials/`, `.git`, `node_modules`, logs out of the image | Docker reads it from the build folder |
| `Dockerfile` | Builds the image (see [14](14-docker-and-cloud-run.md)) | Docker reads it from the build folder |
| `generate_json.py` | Writes `init_embeddings.json`: one random 768-number vector with the id `init_0001` | The workflow runs `python generate_json.py` |
| `init_embeddings.json` | Output of the above. A Vector Search index must start with at least one vector; this is it. The workflow deletes it from the index afterwards | Copied to the bucket during provisioning |
| `index_metadata.json` | **Example** of the index's creation settings (768 dimensions, dot-product distance…). The workflow writes its own copy at deploy time with your real bucket; Terraform has the same values written as code. The `YOUR_PROJECT_ID` in it is a placeholder | Reference for the reader |

---

## 6. Other folders

| Folder | Contents |
|---|---|
| `.github/workflows/deploy.yml` | The deployment pipeline ([16](16-cicd-github-actions.md)) |
| `infra/terraform/` | Optional Terraform version of the provisioning: `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars.example` ([15](15-provisioning-how-resources-are-created.md)) |
| `docs/` | This guide, plus `docs/examples/` with six small runnable programs |
| `course/` | Notes for instructors, and `course/sample_docs/` with four fictional PDFs for trying the app |
| `Supporting Documents/` | `architecture_diagram.png` |

### Folders that appear on your computer but are not in Git

| Folder | Created by | Why it is not committed |
|---|---|---|
| `.venv/` | `python -m venv` | Your private Python environment; recreate it from `requirements.txt` |
| `frontend/node_modules/` | `npm install` | Downloaded packages; recreate from `package-lock.json` |
| `frontend/dist/` | `npm run build` | Build output; Docker rebuilds it |
| `backend/logs/`, `logs/` | the logger | Local diary files |
| `__pycache__/`, `.pytest_cache/` | Python, pytest | Caches |
| `credentials/` | you | Holds secrets |
| `.env` | you | Holds secrets |

---

## 7. How the pieces work together (preview)

```
Browser ─► frontend/src/lib/api.ts ─► backend/api/endpoints.py ─┬─► backend/rag/*   ─► Vertex AI, Gemini
                                                                └─► backend/agent/* ─► Gemini
                    every module reads:  backend/config/settings.py   and writes:  backend/logger/*
```

[05 · Architecture and flows](05-architecture-and-flows.md) follows a real request through these files step by step.

---

## 8. Which parts need which accounts?

| Part | Gemini key | Google Cloud |
|---|:---:|:---:|
| `/api/health`, `/api/status` | – | – |
| `/api/agent/audit` | ✔ | – |
| `/api/rag/ask`, `/api/rag/upload`, `/api/rag/ingest-gcs` | ✔ | ✔ |
| `docs/examples/*` | – | – |
| `pytest backend/tests` | – | – |

---

## 9. Exercise: find it yourself

Open the repository and answer without searching the internet:

1. Which file decides the chunk size? *(Answer: `backend/rag/data_ingestion.py`, `CHUNK_SIZE`.)*
2. Where is the instruction that tells the CFO step what `RED ALERT` means? *(`backend/agent/prompts.py`.)*
3. If the Gemini model is retired, which file or setting do you change? *(`VERTEX_LLM_MODEL_NAME` in `.env`; default in `backend/config/settings.py`.)*
4. Which file would you edit to make the page's tab order different? *(`frontend/src/pages/Index.tsx`.)*
5. Which file creates the cloud storage bucket? *(`.github/workflows/deploy.yml`; or `infra/terraform/main.tf` if you use Terraform.)*
6. Which file stops your API key from being baked into the Docker image? *(`.dockerignore`.)*
