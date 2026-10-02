# Examples

Small programs that show one idea each. **None needs a Google Cloud account or an API key.** Run them from this folder after installing the project requirements (`pip install -r requirements.txt` at the project root, with the virtual environment active).

| File | Idea | Related document |
|---|---|---|
| `01_fastapi_hello.py` | Routes, path and query parameters, validation | [08](../08-backend-api.md), [09](../09-fastapi-deep-dive.md) |
| `02_logging_demo.py` | Plain vs structured logs, log levels | [10](../10-configuration-and-logging.md) |
| `03_chunking_demo.py` | How documents are cut into chunks, and overlap | [11](../11-rag-pipeline.md) |
| `04_tool_demo.py` | What an agent sees when you give it a tool | [12](../12-agents.md) |
| `05_similarity_demo.py` | The maths of "closest meaning" | [11](../11-rag-pipeline.md) |
| `06_settings_demo.py` | Configuration from environment variables | [04](../04-project-tour.md), [10](../10-configuration-and-logging.md) |

```bash
cd docs/examples
python 02_logging_demo.py
python 03_chunking_demo.py
uvicorn 01_fastapi_hello:app --reload --port 8001     # then open http://localhost:8001/docs
```
