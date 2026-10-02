# 10 · Configuration and logging

Two small packages, `backend/config/` and `backend/logger/`, are used by almost every other file. Understanding them removes a lot of mystery from the rest of the code.

---

## Part A · Configuration

### A1. The problem

The program needs values that differ between computers and must sometimes stay secret: the project ID, the bucket, the model name, the API key. If they were typed into the code you would have to edit code to change them, and secrets would be committed to Git.

### A2. The solution: environment variables

An **environment variable** is a named value held by the operating system for a running program. Examples: `GOOGLE_API_KEY`, `GCP_REGION`. Your Python code can read them with `os.environ`. You can see them:

```bash
export GCP_REGION=europe-west1       # set one for this terminal
echo $GCP_REGION                      # read it back
```

### A3. Where the values come from, in priority order

| Priority | Source | Typical use |
|---|---|---|
| 1 (highest) | A real environment variable | Cloud Run, Docker `-e`, a one-off `GCP_REGION=x python ...` |
| 2 | The `.env` file in the folder you run from | Your computer |
| 3 | The default written in `settings.py` | Sensible fallback |

Run `docs/examples/06_settings_demo.py` and then `GCP_REGION=europe-west1 python 06_settings_demo.py` to watch priority 1 beat priority 3.

### A4. `backend/config/settings.py`

```python
class Settings(BaseSettings):
    app_name: str = "Meridian AI - Procurement Intelligence"
    GOOGLE_API_KEY: str = Field("", validation_alias="GOOGLE_API_KEY")
    GCP_PROJECT: str = Field("", validation_alias="GCP_PROJECT_ID")
    llm_model_name: str = Field("gemini-3.8-flash", validation_alias="VERTEX_LLM_MODEL_NAME")
    llm_temperature: float = Field(0.0, validation_alias="LLM_TEMPERATURE")
    ...
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

settings = Settings()
```

- Each attribute is a setting. `validation_alias` is the **environment variable name** to read (the Python name and the variable name differ for some, e.g. `GCP_PROJECT` ← `GCP_PROJECT_ID`).
- Types are enforced: `LLM_TEMPERATURE=abc` stops the program with a clear error; `"0.5"` becomes the number `0.5`.
- `env_file=".env"` is **relative to the folder you run from**. That is why commands must be run from the project root.
- `extra="ignore"` lets `.env` contain variables the class does not list.
- `settings = Settings()` is created once, at import. Every module does `from config.settings import settings`.

At the bottom of the file, if `GCP_SERVICE_ACCOUNT_PATH` points to an existing file, the code sets the standard variable `GOOGLE_APPLICATION_CREDENTIALS` so Google's libraries find your key.

### A5. The complete list of settings

| `.env` name | Python attribute | Default | Used by |
|---|---|---|---|
| `ENVIRONMENT` | `app_env` | `""` | information only |
| `GOOGLE_API_KEY` | `GOOGLE_API_KEY` | `""` | `rag/llm.py` |
| `GCP_PROJECT_ID` | `GCP_PROJECT` | `""` | Vertex AI, Storage |
| `GCP_REGION` | `GCP_REGION` | `""` | Vertex AI |
| `GCS_BUCKET_NAME` | `GCS_BUCKET_NAME` | `""` | uploads, staging, log upload |
| `GCS_PREFIX` | `GCS_PREFIX` | `""` | folder for uploads (use `uploads/`) |
| `GCP_SERVICE_ACCOUNT_PATH` | `gcp_service_account_path` | `""` | credentials file |
| `VERTEX_LLM_MODEL_NAME` | `llm_model_name` | `gemini-3.8-flash` | chat model |
| `LLM_TEMPERATURE` | `llm_temperature` | `0.0` | randomness of answers |
| `VERTEX_EMBEDDING_MODEL_NAME` | `embedding_model_name` | `text-embedding-005` | embeddings (768 numbers) |
| `VECTOR_SEARCH_INDEX_ID` | `vector_search_index_id` | `""` | vector database |
| `VECTOR_SEARCH_INDEX_ENDPOINT_ID` | `vector_search_index_endpoint_id` | `""` | vector database |

### A6. Where each environment keeps its settings

| Place | Mechanism |
|---|---|
| Your computer | `.env` file (never committed) |
| Docker locally | `docker run --env-file .env` |
| Cloud Run | `--set-env-vars` for plain values and `--update-secrets` for the API key (in `deploy.yml`) |
| GitHub Actions | Repository secrets (`GCP_PROJECT_ID`, `GCP_CREDENTIALS_JSON`, `GOOGLE_API_KEY`) |
| Tests | `backend/tests/conftest.py` sets fake values |

### A7. Rules

1. Never commit `.env` or a service-account file. Both are in `.gitignore` and `.dockerignore`.
2. Add every new setting to `Settings` **and** to `.env.example`.
3. Read settings only through `settings`; never call `os.environ` in other files.

---

## Part B · Logging

### B1. Why log at all?

When a program runs on a server you cannot watch it. Logging is the program writing a **diary**: what it started, what it finished, what went wrong. When a learner says "it doesn't work", the diary is how you find out why. `print()` is not enough because it has no importance level, no timestamp, no structure and cannot be filtered.

### B2. Log levels

Every message has a level that says how serious it is:

| Level | Use for | Example in this project |
|---|---|---|
| `DEBUG` | Detail for developers | (not used) |
| `INFO` | Normal progress | `"Loaded PDF from GCS"`, `"Phase complete"` |
| `WARNING` | Something odd that was handled | `"No chunks extracted, skipping indexing"` |
| `ERROR` | An operation failed | `"Upload failed"`, `"RAG query failed"` |
| `CRITICAL` | The program cannot continue | (not used) |

A logger set to a level shows that level and everything more serious. This project's handlers are set to `INFO`.

### B3. Plain logs vs structured logs

Plain text:

```
2026-10-03 03:40:45 INFO Loaded PDF from GCS blob=policy.pdf pages=12
```

Structured (JSON), one object per line:

```json
{"blob": "policy.pdf", "pages": 12, "timestamp": "2026-10-02T22:10:45Z", "level": "info", "severity": "INFO", "event": "Loaded PDF from GCS"}
```

A person can read the first more easily, but a *program* cannot reliably pick out the number of pages. With the second, a logging service can answer "show all errors", "show everything with pages > 100", "count uploads per hour". The cloud tools used here (Cloud Logging) are built for it.

This project uses **structlog**, a library that produces structured logs. You pass the message and then named facts:

```python
log.info("Loaded PDF from GCS", blob=blob.name, pages=len(docs))
```

Run `docs/examples/02_logging_demo.py` to see both styles side by side.

### B4. How the logger is built — `backend/logger/custom_logger.py`

```python
class CustomLogger:
    def __init__(self, log_dir="logs"):
        self.logs_dir = os.path.join(os.getcwd(), log_dir)       # a "logs" folder where you run the app
        os.makedirs(self.logs_dir, exist_ok=True)
        self._timestamp = datetime.now().strftime('%m_%d_%Y_%H_%M_%S')
        self.log_file_path = os.path.join(self.logs_dir, f"{self._timestamp}.log")
        atexit.register(self.flush_to_gcs)                        # run at program exit
```

`get_logger()` then does three things:

1. **Two destinations** ("handlers"): a `StreamHandler` (the console/terminal) and a `FileHandler` (the file in `logs/`). Both print just the message, because structlog has already formatted it.
2. **A processor chain** (steps each log line passes through, in order):

   | Processor | Effect |
   |---|---|
   | `TimeStamper(fmt="iso", utc=True, key="timestamp")` | adds `"timestamp": "2026-10-02T22:10:45Z"` |
   | `add_log_level` | adds `"level": "info"` |
   | `add_severity` (project code) | adds `"severity": "INFO"`, which Cloud Logging understands |
   | `EventRenamer(to="event")` | stores the message under the key `event` |
   | `JSONRenderer()` | turns the dictionary into one JSON line |

3. Returns a logger object. `cache_logger_on_first_use=True` speeds up later calls.

`logger/__init__.py` creates **one** shared instance and one shared logger:

```python
_LOGGER_INSTANCE = CustomLogger()
GLOBAL_LOGGER = _LOGGER_INSTANCE.get_logger("MeridianAI_Backend")
```

Every module starts with `from logger import GLOBAL_LOGGER as log`, so all log lines go to the same file in the same format.

### B5. Why a `severity` field?

Cloud Run copies everything your program prints to Cloud Logging. Cloud Logging looks for a field named **`severity`** in a JSON line to decide whether an entry is shown as info, warning or error and to let you filter. Without it every line is just "default". The `add_severity` function in `custom_logger.py` copies the level into that field, upper-cased. The original `level` field is kept, so nothing breaks. A unit test (`test_log_lines_carry_a_severity_field_for_cloud_logging`) guards this.

### B6. Why upload logs to Cloud Storage at shutdown?

A container's disk is temporary: when Cloud Run stops the container, the `logs/` folder disappears. `flush_to_gcs()` uploads the day's file to `gs://<bucket>/logs/<timestamp>.log` when the server stops (called from the `lifespan` function in `main.py`, and also through `atexit`). If `GCS_BUCKET_NAME` is empty (local runs, tests) it prints a one-line note and skips. A `_gcs_flushed` flag prevents uploading twice. This is a safety copy; in the cloud you would normally just read the live logs in Cloud Logging.

### B7. What gets logged where

| Event | File | Level |
|---|---|---|
| Frontend not built | `api/main.py` | warning |
| Audit/RAG/ingestion failures | `api/endpoints.py` | error |
| File saved to GCS; chunks created | `api/endpoints.py`, `rag/data_ingestion.py` | info |
| RAG query received/answered | `rag/retrieval.py` | info |
| Each audit phase start/finish, with the result text | `agent/agents.py` | info |

> Logs contain the questions and answers. Do not put confidential data into the sample app, and treat the log files as sensitive.

### B8. Reading logs

| Where | How |
|---|---|
| Your terminal | The JSON lines appear as the server runs |
| `logs/<timestamp>.log` | Same lines, saved. `grep '"severity": "ERROR"' logs/*.log` finds errors |
| Cloud Run | Console → Cloud Run → your service → **Logs** (or **Logs Explorer**). Filter `severity>=ERROR`, or text such as `Upload failed` |
| Bucket | `gs://<bucket>/logs/` after the server stopped |

Uvicorn's own access lines (`INFO: 127.0.0.1 - "POST /api/rag/ask" 200`) use Python's standard logging format, not JSON. That is normal.

### B9. Adding your own log line

```python
from logger import GLOBAL_LOGGER as log

log.info("Vendor screened", vendor=vendor_name, result="CLEARED")
log.error("Credit lookup failed", vendor=vendor_name, error=str(e))
```

Guidelines: one event per line, a short constant message, and facts as keyword arguments (not glued into the message). Never log keys, passwords or whole documents.

### B10. Exercises

1. Start the backend and call `GET /api/health`. Open `logs/` and find the newest file. What is in it?
2. Run an audit and follow the phase lines in the terminal.
3. Add a `log.info` line to `rag/retrieval.py` that records `len(response["answer"])`.
4. Run `docs/examples/02_logging_demo.py`; add a `log.warning(...)` of your own.
5. Cause an error (empty `VECTOR_SEARCH_INDEX_ID`) and find the resulting `"level": "error"` line.
