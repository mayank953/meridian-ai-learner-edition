# 09 · FastAPI in depth

[08](08-backend-api.md) shows this project's API files. This page explains the ideas underneath, so that you understand *why* the code is written the way it is. The runnable file `docs/examples/01_fastapi_hello.py` goes with this page.

---

## 1. What is a web API, concretely?

A program on one computer (the *client*) sends a text message to a program on another (the *server*), and gets a text message back. The rules of the conversation are called **HTTP**.

A request has:

| Part | Example | Meaning |
|---|---|---|
| **Method** | `POST` | What kind of action. `GET` = read, `POST` = send data to be processed, `PUT`/`PATCH` = update, `DELETE` = remove |
| **URL / path** | `/api/rag/ask` | Which thing you are talking to |
| **Query string** | `?shout=true` | Optional extra settings in the URL |
| **Headers** | `Content-Type: application/json` | Information about the message |
| **Body** | `{"query": "What is..."}` | The data itself (for `POST`) |

A response has a **status code** and (usually) a body:

| Code | Meaning | Where this project returns it |
|---|---|---|
| `200` | OK | normal success |
| `400` | Bad request | `POST /api/rag/upload` with no files |
| `404` | Not found | an unknown `/api/...` URL |
| `422` | Your data has the wrong shape | FastAPI, automatically, when the body does not match the schema |
| `500` | The server failed | any exception in a route (the message is in `detail`) |

**JSON** is the text format both sides use: `{"query": "hello", "retriever_type": "similarity"}`. It maps directly to Python dictionaries and lists.

You can watch real traffic: in a browser press F12 → **Network**, click a button in the app, and click the request.

## 2. What FastAPI does for you

You write ordinary Python functions. FastAPI:

1. matches the incoming URL and method to a function (**routing**);
2. converts the request into Python values and **checks** them against your type hints (**validation**);
3. calls your function;
4. converts the return value into JSON (**serialisation**), checking it against `response_model` if you gave one;
5. generates interactive documentation at `/docs` and a machine-readable description at `/openapi.json`.

Look at this route from the project:

```python
@rag_router.post("/ask", response_model=QueryResponse)
def rag_query(payload: QueryRequest):
    return QueryResponse(answer=ask_question(payload.query, payload.retriever_type))
```

Everything is declared by the *type hint* `payload: QueryRequest`. FastAPI reads it and knows: "the body must be JSON, with a `query` string and an optional `retriever_type` string".

## 3. FastAPI, Uvicorn and ASGI

- **FastAPI** is the framework: your routes and rules.
- **Uvicorn** is the server process that listens on a network port, receives the raw bytes, and passes requests to FastAPI.
- **ASGI** is the agreed interface between them. It is why you start the app with `uvicorn api.main:app`: *module path* `api.main`, then the *variable* `app` inside it.
- `--reload` restarts the server when you save a file (development only). `--port 8080` chooses the port. `--app-dir backend` adds the `backend/` folder to Python's search path.

## 4. The life of one request

```
 client ─► Uvicorn ─► middleware (CORS) ─► router matches path+method
                                              │
                      validate path/query/body against type hints  ──► 422 if wrong
                                              │
                                  your function runs  ──► exception? ──► 500 (or your HTTPException)
                                              │
                      check/convert result with response_model
                                              │
 client ◄── Uvicorn ◄── middleware ◄───── response
```

## 5. Pydantic: the data-checking engine

A Pydantic model is a class whose attributes have types:

```python
class QueryRequest(BaseModel):
    query: str
    retriever_type: str = "similarity"   # has a default → optional
```

- `{"query": "hi"}` is accepted; `retriever_type` becomes `"similarity"`.
- `{}` is rejected: *Field required*.
- `{"query": 5}` — Pydantic tries to convert; failing that, it is rejected.

The same library powers **settings**: `pydantic-settings` reads environment variables and converts the text `"0.0"` into the number `0.0` ([10](10-configuration-and-logging.md)).

Try `docs/examples/01_fastapi_hello.py`: it adds a rule `quantity > 0` and shows the exact error messages.

## 6. Routers: keeping routes organised

```python
health_router = APIRouter(prefix="/api", tags=["Health"])
rag_router    = APIRouter(prefix="/api/rag", tags=["RAG"])

@rag_router.post("/ask")        # full path: /api/rag/ask
```

- `prefix` is added in front of every route in the router.
- `tags` group the routes in `/docs`.
- `app.include_router(rag_router)` in `main.py` plugs the group into the app.

Why use routers? In a small app you could write `@app.post(...)` everywhere. Routers let you define routes in one file and assemble the app in another, which is how `endpoints.py` and `main.py` are split.

## 7. `def` or `async def`? (the most confusing FastAPI topic)

A server handles many requests at the same time. There are two ways to do that:

| Style | How it works | In this project |
|---|---|---|
| **`def` (normal function)** | FastAPI runs it in a **thread pool**: a set of helper threads. While one thread waits for Gemini, other threads serve other requests | Almost every route |
| **`async def`** | Runs on the main **event loop**. Inside it you use `await` for operations that wait (network, files). While one request awaits, the loop serves others. **But any slow, non-awaited code inside blocks everybody** | `upload_documents` |

`upload_documents` is `async def` because it must `await upload.read()` to read the file. But embedding PDF text is slow, ordinary Python. Running it directly would freeze the event loop, so even `/api/health` would stop answering. The fix is in the code:

```python
summary = await run_in_threadpool(ingest_pdf, local_path, f"upload://{upload.filename}")
```

`run_in_threadpool` moves the slow function onto a helper thread and `await`s its result.

Rule of thumb: **use plain `def` unless you need `await`; never run slow blocking code directly inside `async def`.**

## 8. Errors

Any exception that nobody catches becomes a bare `500 Internal Server Error`. The routes here catch exceptions, log them, and raise:

```python
raise HTTPException(status_code=500, detail=str(e))
```

This returns `{"detail": "..."}`. The React code in `api.ts` reads `body.detail` and shows it to the user, so the real error is visible in the browser, not only in the terminal. (In a public production system you might hide internal error text from users.)

## 9. Middleware and CORS

**Middleware** is code that wraps every request and response. This project uses one: `CORSMiddleware`.

**The problem CORS solves:** a browser, for safety, stops a web page from `http://localhost:3000` calling an API at a *different origin* (`http://localhost:8080`) unless the API says that is allowed. Before the real request the browser sends a small "preflight" `OPTIONS` request asking permission. The middleware answers it.

```python
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True,
                   allow_methods=["*"], allow_headers=["*"])
```

`allow_origins=["*"]` means *any* website may call this API from a browser. That is convenient while learning. In production you list your own site(s). When the app runs in Docker/Cloud Run, the page and the API come from the same address, so CORS does not apply at all.

If you ever see *"blocked by CORS policy"* in the browser console, the API is unreachable or answered with an error that lacked the CORS headers. See [18](18-troubleshooting.md).

## 10. Lifespan: running code at start and stop

```python
@asynccontextmanager
async def lifespan(app):
    yield                              # the app serves requests while paused here
    _LOGGER_INSTANCE.flush_to_gcs()    # runs once, on shutdown
```

Code before `yield` runs at startup; code after runs at shutdown. This project uses only the shutdown half, to upload the log file. (This replaces the older `@app.on_event("shutdown")` decorator, which FastAPI has deprecated.)

## 11. Serving the React app from the same server

In `main.py`, if the folder `frontend/dist` exists, the API also serves the website:

```python
app.mount("/assets", StaticFiles(directory=".../assets"), name="assets")

@app.get("/{catchall:path}", include_in_schema=False)
def serve_frontend(catchall: str): ...
```

Order matters: the routers are registered **first**, so `/api/...` URLs reach your API routes. The *catch-all* route comes last and matches everything else, returning a real file if one exists, otherwise `index.html`, so the browser-side router can show the right page. The function returns a 404 for unknown `/api/` paths so typos in API URLs are not hidden behind the web page, and it checks that the requested file is inside `dist/` so nobody can read other files on the server.

## 12. Dependencies with `lru_cache`: create once, reuse

```python
@lru_cache(maxsize=1)
def get_supervisor() -> ProcurementSupervisor:
    return ProcurementSupervisor()
```

`lru_cache(maxsize=1)` remembers the result of the first call. Every later call returns the same object without rebuilding. Used for the supervisor, the chat model, the embedding model and the vector-store connection. Two benefits: nothing expensive happens at import time, and each object is created exactly once.

(FastAPI also has its own `Depends(...)` system for sharing resources. This project does not need it.)

## 13. Testing the API without a server

FastAPI includes `TestClient`, which calls your app in memory:

```python
from fastapi.testclient import TestClient
client = TestClient(app)
assert client.get("/api/health").json() == {"status": "ok"}
```

To test a route that would call Gemini, replace the function it calls with a stand-in. `monkeypatch` is a pytest tool for swapping things temporarily:

```python
monkeypatch.setattr(endpoints, "ask_question", lambda query, retriever_type: "stub answer")
res = client.post("/api/rag/ask", json={"query": "hello"})
assert res.json() == {"answer": "stub answer"}
```

This works because `endpoints.py` calls `ask_question` as a name inside its own module. See `backend/tests/test_api.py`.

## 14. Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Starting uvicorn from the wrong folder | `ModuleNotFoundError: No module named 'api'` | Run from the project root with `--app-dir backend` |
| Slow code inside `async def` | The whole server freezes during one request | Use `def`, or `run_in_threadpool` |
| Forgetting `response_model` fields | Extra data silently dropped or missing | Match the model to what you return |
| Reading settings at import time from an unset variable | Value is empty | Run from the folder that holds `.env`; check `/api/status` |
| Catch-all route placed before API routers | Every `/api/...` call returns the web page | Register routers first |

## 15. Exercises

1. Run `docs/examples/01_fastapi_hello.py`; in `/docs` trigger each of the 422 and 400 responses.
2. Add a `DELETE /orders/{id}` route and look at it in `/docs`.
3. Make a slow route with `async def` and `time.sleep(10)`, then call `/hello` in another tab. Change `async def` to `def` and repeat. What changes?
4. In the main project, send `POST /api/rag/ask` with an empty body. Read the 422 message.
