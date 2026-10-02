# 03 · Project basics — what is in a software project, and why

Read this if any of these words are unfamiliar: *repository, package, module, virtual environment, requirements file, environment variable, `.env`, API, frontend, backend, container, pipeline*. If you already know them, go straight to [04 · Project tour](04-project-tour.md).

This page explains the *ideas*. Document 04 then shows where each idea lives in this project.

---

## 1. A project is more than code

When you first learn to program, a "program" is one file. A real application is a **folder of many files**, and they fall into a few kinds. Knowing the kind tells you how to treat a file.

| Kind of file | Examples in this project | How you treat it |
|---|---|---|
| **Source code**: instructions the computer runs | `backend/rag/retrieval.py`, `frontend/src/lib/api.ts` | You read and edit it |
| **Configuration**: settings that change behaviour without changing code | `.env`, `requirements.txt`, `package.json`, `Dockerfile` | You edit values, carefully |
| **Secrets**: keys and passwords | the Gemini API key in `.env`, `credentials/*.json` | **Never commit them to Git** |
| **Data / assets**: inputs the program uses | `course/sample_docs/*.pdf`, `init_embeddings.json` | You supply or replace them |
| **Documentation**: explanations for people | `README.md`, everything in `docs/` | You read it and keep it up to date |
| **Automation**: scripts that run for you | `.github/workflows/deploy.yml` | You trigger it; it runs on a server |
| **Generated files**: created by tools, not written by hand | `frontend/dist/`, `__pycache__/`, `node_modules/` | **Never edit by hand; not committed** |

## 2. Repository, Git and GitHub

- A **repository** (repo) is the project folder plus its complete history of changes.
- **Git** is the tool that records that history. A **commit** is one saved set of changes with a message. A **branch** is a separate line of work.
- **GitHub** is a website that stores repositories so people can share and collaborate.
- **`.gitignore`** lists files Git must not track: secrets, generated files, your personal settings. This is the main reason a secret does not end up on the internet by accident.

## 3. Frontend and backend

Most web applications are split in two:

```
 Your browser                                A computer running your Python code
┌──────────────────┐   requests (HTTP)     ┌───────────────────────────────┐
│ FRONTEND         │ ───────────────────►  │ BACKEND                       │
│ what you see:    │                       │ the logic: reads documents,   │
│ buttons, tabs    │ ◄───────────────────  │ calls AI models, returns data │
└──────────────────┘   responses (JSON)    └───────────────────────────────┘
```

- The **frontend** runs in the user's browser. In this project it is written in TypeScript with React.
- The **backend** runs on a server. In this project it is written in Python with FastAPI.
- They communicate through an **API**: a list of addresses (URLs) the backend offers, each doing one job, exchanging data as **JSON** (plain text structured like a Python dictionary).

Why separate them? Each has its own tools, its own language, and can be changed without touching the other. The frontend does not need to know *how* an answer is produced, only *which address to ask*.

## 4. Python project vocabulary

| Term | Meaning | Where you see it here |
|---|---|---|
| **Module** | One `.py` file you can `import` | `retrieval.py` |
| **Package** | A folder of modules, marked by an `__init__.py` file | `backend/rag/` |
| **Import** | Using code from another module | `from rag.llm import get_llm` |
| **Dependency** | A package written by someone else that your code uses | `fastapi`, `langchain` |
| **`requirements.txt`** | A list of dependencies and versions | root of the project |
| **Virtual environment** | A private copy of Python and packages for one project, so projects do not interfere | the `.venv/` folder |
| **Pinning** | Writing an exact version (`fastapi==0.135.1`) so everyone gets identical behaviour | `requirements.txt` |

The usual routine:

```bash
python3.12 -m venv .venv          # create the private environment (once)
source .venv/bin/activate         # switch it on (each new terminal)
pip install -r requirements.txt   # install the dependencies
```

If you forget to activate the environment, Python cannot find the packages and you see `ModuleNotFoundError`.

## 5. Configuration: settings kept out of code

Some values change between computers or between "my laptop" and "the live server": a project ID, a bucket name, a model name. And some values are secret: an API key. Putting these inside the code is a bad idea because:

1. changing them means editing code;
2. secrets would be committed to Git and visible to everyone.

The standard solution is **environment variables**: named values that exist outside your code, in the operating system's environment. Your code asks for them by name.

For convenience on your own computer, a `.env` file holds them:

```
GOOGLE_API_KEY=abc123
GCP_PROJECT_ID=my-project
```

The program reads `.env` when it starts. `.env` is listed in `.gitignore` so it is never committed. `.env.example` is a **template** with the names but no real values, and *is* committed, so you know what to fill in.

On the live server there is no `.env`; the values are supplied by the hosting platform (Cloud Run environment variables and Secret Manager).

## 6. Layers, modules and "one job per file"

A good project is split so that each piece has **one job** and you can find things by name. The split used here:

| Question | Answer in this project |
|---|---|
| Where is the code that answers HTTP requests? | `backend/api/` |
| Where is the code that deals with documents and AI search? | `backend/rag/` |
| Where is the agent code? | `backend/agent/` |
| Where are the settings? | `backend/config/` |
| Where is the logging? | `backend/logger/` |
| Where is the screen the user sees? | `frontend/` |

If something breaks, the error message tells you which area to open. Details and reasons are in [04](04-project-tour.md) and [19](19-design-decisions-the-why.md).

## 7. Containers, the cloud and automation

| Idea | One-paragraph explanation |
|---|---|
| **Cloud provider** | A company (here Google) that rents you computers, storage and services by the hour, over the internet, instead of you buying hardware |
| **Project (Google Cloud)** | A named account-like space that holds all your resources and your bill |
| **Docker image / container** | A sealed package containing your app *and* the exact environment it needs. Anyone can run it and get the same result. A **container** is a running copy |
| **Provisioning** | Creating the cloud resources your app needs (storage, database, servers). See [15](15-provisioning-how-resources-are-created.md) |
| **Deployment** | Putting a new version of your app onto those resources so people can use it |
| **CI/CD** | *Continuous Integration / Continuous Delivery*: a robot that builds, tests and deploys your code automatically each time you push changes. Here, **GitHub Actions** does this |
| **Logging** | Your program writing a running diary of what it does, so you can understand problems afterwards. See [10](10-configuration-and-logging.md) |

## 8. What the application does (in one paragraph)

You upload PDF documents. The backend cuts them into small pieces, converts each piece into numbers that represent its meaning (an *embedding*), and stores them in a *vector database*. When you ask a question, the backend converts the question the same way, finds the closest stored pieces, and asks Google's Gemini model to answer using only those pieces. Separately, you can submit a purchase request, and three AI "agents" (risk, tax, accounting control) check it using tools, after which a final step writes a summary memo.

## 9. How to read this guide

1. Finish [00](00-overview.md) to [02](02-accounts-credits-costs.md) to know what you are building and what it costs.
2. Read [04 · Project tour](04-project-tour.md) with the repository open next to it. Open each file as it is described.
3. Read [05 · Architecture and flows](05-architecture-and-flows.md) to see how the files work together.
4. Run it ([06](06-google-cloud-setup.md), [07](07-run-locally.md)).
5. Read the deep dives in order: [08](08-backend-api.md) → [09](09-fastapi-deep-dive.md) → [10](10-configuration-and-logging.md) → [11](11-rag-pipeline.md) → [12](12-agents.md) → [13](13-frontend.md).
6. Read how it is shipped: [14](14-docker-and-cloud-run.md) → [15](15-provisioning-how-resources-are-created.md) → [16](16-cicd-github-actions.md).
7. Keep [17](17-cleanup.md), [18](18-troubleshooting.md) and [21](21-glossary.md) nearby.
