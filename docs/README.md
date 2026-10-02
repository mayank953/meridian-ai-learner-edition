# Meridian AI — Learner Guide

This guide takes you from "I have never seen this project" to "I understand every part of it": what each folder and file is for, why the code is organised this way, how the parts work together, and how it gets built and deployed.

It is written like a senior engineer walking a new teammate through a codebase. Nothing is skipped, and new ideas (FastAPI, logging, provisioning, Terraform…) are explained from the beginning.

> **Is Terraform used?** No. The deployment is done by **GitHub Actions running `gcloud` commands**. A Terraform version is included only as an optional learning example. See [15](15-provisioning-how-resources-are-created.md).

## Reading order

### Part 1 · Start here
| # | Document | You will learn |
|---|---|---|
| 00 | [Overview](00-overview.md) | What the project does; three ways to use the repository |
| 01 | [Requirements](01-requirements.md) | Knowledge, accounts, software, time |
| 02 | [Accounts, credits and costs](02-accounts-credits-costs.md) | Gemini key, Google Cloud account, the **$300 / 90-day** trial, what costs money |

### Part 2 · Understand the project (from the basics)
| # | Document | You will learn |
|---|---|---|
| 03 | [Project basics](03-project-basics.md) | What a repository, package, `.env`, API, container and pipeline are |
| 04 | [**Project tour**](04-project-tour.md) | **Every folder and file, what it does, and why the project is divided this way** |
| 05 | [Architecture and flows](05-architecture-and-flows.md) | How the parts work together, traced through real functions |

### Part 3 · Set up and run
| # | Document | You will learn |
|---|---|---|
| 06 | [Google Cloud setup](06-google-cloud-setup.md) | Project, billing, service account, GitHub secrets, first deployment |
| 07 | [Run it on your computer](07-run-locally.md) | Audit-only start, document Q&A, tests, Docker |

### Part 4 · The code in depth
| # | Document | You will learn |
|---|---|---|
| 08 | [The web API](08-backend-api.md) | This project's routes, schemas and settings usage |
| 09 | [FastAPI in depth](09-fastapi-deep-dive.md) | HTTP, validation, `async` vs `def`, CORS, lifespan, testing |
| 10 | [Configuration and logging](10-configuration-and-logging.md) | Environment variables, `.env`, log levels, structured logs, Cloud Logging |
| 11 | [Document Q&A (RAG)](11-rag-pipeline.md) | Chunks, embeddings, Vector Search, retrieval |
| 12 | [The audit agents](12-agents.md) | Tools, prompts, `create_agent`, supervisor |
| 13 | [The user interface](13-frontend.md) | How the React app talks to the backend |

### Part 5 · Shipping it
| # | Document | You will learn |
|---|---|---|
| 14 | [Docker and Cloud Run](14-docker-and-cloud-run.md) | Containers and hosting |
| 15 | [Provisioning](15-provisioning-how-resources-are-created.md) | How cloud resources are created: GitHub Actions + `gcloud` (used) vs Terraform (optional) |
| 16 | [GitHub Actions deployment](16-cicd-github-actions.md) | The automated pipeline, step by step |
| 17 | [Cleanup](17-cleanup.md) | Stop all charges |

### Part 6 · Reference
| # | Document | Contents |
|---|---|---|
| 18 | [Troubleshooting](18-troubleshooting.md) | Symptoms, causes and fixes |
| 19 | [Design decisions: the why](19-design-decisions-the-why.md) | The reason behind each choice, and the learning trade-offs |
| 20 | [Alternatives and next steps](20-alternatives-and-next-steps.md) | Other tools; ideas to extend the project |
| 21 | [Glossary](21-glossary.md) | Plain-English definitions |

### Also in this folder
| Item | What it is |
|---|---|
| [examples/](examples/README.md) | Six small runnable programs (FastAPI, logging, chunking, tools, similarity, settings) that need no cloud account |
| [MERIDIAN_AI_COMPLETE_GUIDE.md](MERIDIAN_AI_COMPLETE_GUIDE.md) | Everything above in a single file (generate with `python docs/build_complete_guide.py`) |

## Quick start (about 20 minutes, no Google Cloud needed)

```bash
git clone <this repository's URL>
cd <the folder you just cloned>
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
cp .env.example .env            # then put your Gemini API key in .env
uvicorn api.main:app --app-dir backend --reload --port 8080
```

Open http://localhost:8080/docs and try the audit endpoint. Full steps: [07](07-run-locally.md).

## Important

- **Aldermoor Industries is fictional.** The sample documents contain made-up data.
- **Cloud features cost money after your free credit.** Read [02](02-accounts-credits-costs.md) and [17](17-cleanup.md) before creating cloud resources.
- **Never commit keys.** `.env` and `credentials/` are ignored by Git; keep it that way.
