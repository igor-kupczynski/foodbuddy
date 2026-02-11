---
name: Mistral AI API
description: Use this skill when integrating an application with the Mistral AI API. It covers models, endpoints, SDKs, and practical patterns.
---

# Mistral AI API Skill

Use this skill when integrating an application with the Mistral AI API. It covers models, endpoints, SDKs, and practical patterns.

> Last updated: 2026-02-10. Source: [docs.mistral.ai](https://docs.mistral.ai/)

---

## Quick Start

**Base URL**: `https://api.mistral.ai/v1/`
**Auth**: `Authorization: Bearer $MISTRAL_API_KEY`
**API keys**: Create at [console.mistral.ai](https://console.mistral.ai)

### curl

```bash
curl "https://api.mistral.ai/v1/chat/completions" \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral-large-latest",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

### Python

```bash
pip install mistralai
```

```python
import os
from mistralai import Mistral

client = Mistral(api_key=os.environ["MISTRAL_API_KEY"])

response = client.chat.complete(
    model="mistral-large-latest",
    messages=[{"role": "user", "content": "Hello!"}],
)
print(response.choices[0].message.content)
```

### TypeScript

```bash
npm add @mistralai/mistralai
```

```typescript
import { Mistral } from "@mistralai/mistralai";

const client = new Mistral({ apiKey: process.env.MISTRAL_API_KEY });

const result = await client.chat.complete({
  model: "mistral-large-latest",
  messages: [{ role: "user", content: "Hello!" }],
});
console.log(result.choices[0].message.content);
```

---

## Models (as of 2026-02)

### Model Selection Guide

| Use Case | Recommended Model | API ID | Why |
|----------|-------------------|--------|-----|
| Complex reasoning, multimodal, enterprise | Mistral Large 3 | `mistral-large-latest` | Best overall, 256k context, vision, tool use |
| Balanced production workloads | Mistral Medium 3.1 | `mistral-medium-latest` | Good perf/cost ratio, 128k context |
| Cost-sensitive general tasks | Mistral Small 3.2 | `mistral-small-latest` | Very cheap ($0.06/$0.18 per M tokens), 128k |
| Budget / simple tasks | Mistral Nemo 12B | `open-mistral-nemo` | Cheapest ($0.02/$0.04 per M tokens), 128k |
| Math, logic, chain-of-thought | Magistral Medium 1.2 | `magistral-medium-latest` | Explicit reasoning traces, 40k context |
| Budget reasoning | Magistral Small 1.2 | `magistral-small-latest` | Cheaper reasoning, 40k context |
| Code completion (IDE / FIM) | Codestral | `codestral-latest` | FIM support, 256k, 80+ languages |
| Agentic coding / tool use for SWE | Devstral 2 | `devstral-small-latest` | 256k, 123B params, coding-focused |
| Edge / mobile / low-latency | Ministral 3B/8B/14B | `ministral-*b-2512` | Small, fast, still vision-capable |
| Document OCR | Mistral OCR 3 | `mistral-ocr-latest` | $2/1000 pages, preserves structure |
| Text embeddings | Mistral Embed | `mistral-embed` | 1024 dims, 8k context |
| Code embeddings | Codestral Embed | `codestral-embed` | 1536 dims (up to 3072) |

### Detailed Model Specs

#### Flagship Generalist Models

| Model | API ID | Params | Context | Input $/M | Output $/M |
|-------|--------|--------|---------|-----------|------------|
| Mistral Large 3 (v25.12) | `mistral-large-2512` | 675B total (41B active, MoE) | 256k | $0.50 | $1.50 |
| Mistral Medium 3.1 (v25.08) | `mistral-medium-2508` | -- | 128k | $0.40 | $2.00 |
| Mistral Small 3.2 (v25.06) | `mistral-small-2506` | 24B | 128k | $0.06 | $0.18 |

Aliases: `mistral-large-latest`, `mistral-medium-latest`, `mistral-small-latest`.

#### Small / Edge Models

| Model | API ID | Context | Input $/M | Output $/M |
|-------|--------|---------|-----------|------------|
| Ministral 3 14B (v25.12) | `ministral-14b-2512` | 128k | $0.20 | $0.20 |
| Ministral 3 8B (v25.12) | `ministral-8b-2512` | 128k | $0.15 | $0.15 |
| Ministral 3 3B (v25.12) | `ministral-3b-2512` | 128k | $0.10 | $0.10 |
| Mistral Nemo 12B (v24.07) | `open-mistral-nemo` | 128k | $0.02 | $0.04 |

#### Reasoning Models (Magistral)

| Model | API ID | Context | Input $/M | Output $/M |
|-------|--------|---------|-----------|------------|
| Magistral Medium 1.2 (v25.09) | `magistral-medium-2509` | 40k | ~$2.00 | ~$5.00 |
| Magistral Small 1.2 (v25.09) | `magistral-small-2509` | 40k | ~$0.50 | ~$1.50 |

Aliases: `magistral-medium-latest`, `magistral-small-latest`.

#### Code Models

| Model | API ID | Context | Input $/M | Output $/M | Notes |
|-------|--------|---------|-----------|------------|-------|
| Codestral (v25.08) | `codestral-2508` | 256k | $0.30 | $0.90 | FIM + chat, 80+ languages |
| Devstral 2 (v25.12) | `devstral-2512` | 256k | $0.05 | $0.22 | Agentic coding, 123B |

Aliases: `codestral-latest`, `devstral-small-latest`.
Codestral endpoint: `https://codestral.mistral.ai/v1/` (preferred for IDE integrations).

### Vision Support

Models with vision: **Mistral Large 3**, **Mistral Medium 3.1**, **Mistral Small 3.2**, **Ministral 3 14B/8B/3B**.

Max 8 images per request, max 10 MB per image.

### Production Tip

Use specific version IDs (e.g. `mistral-large-2512`) in production for stability. Use `-latest` aliases during development.

**Naming convention**: API model IDs use `{family}-{YYMM}` format (e.g. `mistral-large-2512` for December 2025). Don't confuse these with docs URL slugs which use a different format (e.g. `mistral-large-3-25-12` in `docs.mistral.ai/models/mistral-large-3-25-12`).

---

## Chat Completions API

### Endpoint

`POST https://api.mistral.ai/v1/chat/completions`

### Request Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model` | string | **required** | Model ID |
| `messages` | array | **required** | Conversation messages |
| `temperature` | number | model default | 0.0-1.0 (recommend 0.0-0.7) |
| `top_p` | number | 1 | Nucleus sampling (0-1) |
| `max_tokens` | integer | -- | Max output tokens |
| `min_tokens` | integer | -- | Min output tokens |
| `stream` | boolean | false | Enable SSE streaming |
| `stop` | string/array | -- | Stop sequence(s) |
| `random_seed` | integer | -- | For reproducibility |
| `frequency_penalty` | number | 0 | Token frequency penalty [-2, 2] |
| `presence_penalty` | number | 0 | Token presence penalty [-2, 2] |
| `safe_prompt` | boolean | false | Inject safety system prompt |
| `tools` | array | null | Function/tool definitions |
| `tool_choice` | string/object | -- | `"auto"`, `"none"`, `"any"`, `"required"` |
| `parallel_tool_calls` | boolean | true | Allow parallel tool calls |
| `response_format` | object | null | `{"type": "json_object"}` or `{"type": "json_schema", ...}` |
| `prompt_mode` | string | -- | Set `"reasoning"` for Magistral models |

### Message Roles

- `system` -- Instructions/context for the assistant
- `user` -- Human messages (text or multipart with images)
- `assistant` -- Model responses (can be prefilled for few-shot)
- `tool` -- Tool execution results (must include `tool_call_id`)

### Response Shape

```json
{
  "id": "chat-abc123",
  "object": "chat.completion",
  "model": "mistral-large-latest",
  "choices": [{
    "index": 0,
    "message": {"role": "assistant", "content": "..."},
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 25,
    "completion_tokens": 10,
    "total_tokens": 35
  }
}
```

---

## Streaming

Set `stream: true`. Responses arrive as Server-Sent Events. Stream ends with `data: [DONE]`.

### Python

```python
stream = client.chat.stream(
    model="mistral-large-latest",
    messages=[{"role": "user", "content": "Tell me a story"}],
)
for chunk in stream:
    content = chunk.data.choices[0].delta.content
    if content:
        print(content, end="")
```

### TypeScript

```typescript
const stream = await client.chat.stream({
  model: "mistral-large-latest",
  messages: [{ role: "user", content: "Tell me a story" }],
});
for await (const chunk of stream) {
  const content = chunk.data.choices[0].delta.content;
  if (content) process.stdout.write(content);
}
```

---

## Async (Python)

```python
import asyncio
from mistralai import Mistral

async def main():
    async with Mistral(api_key=os.environ["MISTRAL_API_KEY"]) as client:
        response = await client.chat.complete_async(
            model="mistral-large-latest",
            messages=[{"role": "user", "content": "Hello!"}],
        )
        print(response.choices[0].message.content)

asyncio.run(main())
```

Async streaming: use `client.chat.stream_async(...)`.

---

## Function Calling / Tool Use

Supported by: Large 3, Medium 3.1, Small 3.2, Devstral, Magistral, Codestral.

### 1. Define tools

```python
tools = [{
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Get the current weather in a location",
        "parameters": {
            "type": "object",
            "properties": {
                "location": {"type": "string", "description": "City name"},
                "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
            },
            "required": ["location"]
        }
    }
}]
```

### 2. Send request with tools

```python
response = client.chat.complete(
    model="mistral-large-latest",
    messages=[{"role": "user", "content": "What is the weather in Paris?"}],
    tools=tools,
    tool_choice="auto",  # "auto" | "any"/"required" | "none"
)
```

### 3. Handle tool calls

```python
import json

message = response.choices[0].message

if message.tool_calls:
    # Execute each tool call
    tool_results = []
    for tc in message.tool_calls:
        args = json.loads(tc.function.arguments)
        result = call_your_function(tc.function.name, args)  # your logic
        tool_results.append({
            "role": "tool",
            "tool_call_id": tc.id,
            "content": json.dumps(result),
        })

    # Send results back for final response
    messages = [
        {"role": "user", "content": "What is the weather in Paris?"},
        message,           # assistant message with tool_calls
        *tool_results,     # tool results
    ]
    final = client.chat.complete(
        model="mistral-large-latest",
        messages=messages,
        tools=tools,
    )
    print(final.choices[0].message.content)
```

### tool_choice values

- `"auto"` (default) -- model decides whether to call tools
- `"any"` / `"required"` -- model must call at least one tool
- `"none"` -- model must not call tools

Set `parallel_tool_calls: false` to force sequential tool calls.

---

## Structured Output / JSON Mode

### JSON mode (any valid JSON)

```python
response = client.chat.complete(
    model="mistral-large-latest",
    messages=[{"role": "user", "content": "List 3 EU countries as JSON"}],
    response_format={"type": "json_object"},
)
```

### JSON Schema mode (validated against schema)

```python
response = client.chat.complete(
    model="mistral-large-latest",
    messages=[{"role": "user", "content": "List 3 EU countries"}],
    response_format={
        "type": "json_schema",
        "json_schema": {
            "name": "countries",
            "schema": {
                "type": "object",
                "properties": {
                    "countries": {
                        "type": "array",
                        "items": {"type": "string"}
                    }
                },
                "required": ["countries"]
            }
        }
    },
)
```

### Parsed structured output (Python SDK with Pydantic)

```python
from pydantic import BaseModel

class Book(BaseModel):
    name: str
    authors: list[str]

response = client.chat.parse(
    model="mistral-large-latest",
    messages=[{"role": "user", "content": "What is the best book about Python?"}],
    response_format=Book,
    temperature=0,
)
book = response.choices[0].message.parsed  # typed Book instance
```

TypeScript equivalent uses Zod schemas with `client.chat.parse(...)`.

---

## Vision (Multimodal)

```python
response = client.chat.complete(
    model="mistral-large-latest",
    messages=[{
        "role": "user",
        "content": [
            {"type": "text", "text": "Describe this image"},
            {"type": "image_url", "image_url": "https://example.com/photo.jpg"},
        ]
    }],
)
```

Base64 images: `{"type": "image_url", "image_url": "data:image/jpeg;base64,..."}`.

---

## Embeddings

### Text embeddings

```python
response = client.embeddings.create(
    model="mistral-embed",
    inputs=["First document", "Second document"],
)
vector = response.data[0].embedding  # list of 1024 floats
```

### Code embeddings

```python
response = client.embeddings.create(
    model="codestral-embed",
    inputs=["def hello(): print('hi')"],
    # Optional: output_dimension=1024, encoding_format="float"
)
```

---

## Code Generation (FIM)

Fill-in-the-middle via the dedicated endpoint. Use Codestral.

**Endpoint**: `POST https://codestral.mistral.ai/v1/fim/completions`

```python
# Note: use codestral endpoint for FIM
from mistralai import Mistral

client = Mistral(api_key=os.environ["CODESTRAL_API_KEY"])

response = client.fim.complete(
    model="codestral-latest",
    prompt="def fibonacci(n: int):",
    suffix="n = int(input('Enter a number: '))\nprint(fibonacci(n))",
    temperature=0,
    max_tokens=256,
)
print(response.choices[0].message.content)
```

---

## Reasoning (Magistral Models)

Magistral models produce thinking traces before the final answer.

```python
response = client.chat.complete(
    model="magistral-medium-latest",
    messages=[{"role": "user", "content": "Prove that sqrt(2) is irrational"}],
    # prompt_mode="reasoning" is the default for Magistral
)
# Response contains thinking + text content blocks
for block in response.choices[0].message.content:
    if block.type == "thinking":
        print(f"[Thinking]: {block.content}")
    elif block.type == "text":
        print(f"[Answer]: {block.content}")
```

---

## OCR

```python
response = client.ocr.process(
    model="mistral-ocr-latest",
    document={"type": "document_url", "document_url": "https://example.com/doc.pdf"},
    # Options: table_format="html", extract_footer=True, extract_header=True
)
# Returns markdown with extracted text, tables, and image references
```

---

## Agents API

Create pre-configured model instances with built-in tools.

```python
# Create an agent
agent = client.beta.agents.create(
    model="mistral-medium-latest",
    name="Research Assistant",
    description="Helps with research",
    instructions="You are a research assistant. Be thorough and cite sources.",
    tools=[{"type": "web_search"}],  # built-in tools: web_search, code_interpreter, image_generation
)

# Start a conversation
response = client.beta.conversations.start(
    agent_id=agent.id,
    inputs="Find recent papers on transformer architectures",
)
```

---

## Fine-Tuning

```python
# 1. Upload training data (JSONL with messages format)
uploaded = client.files.upload(file=open("train.jsonl", "rb"), purpose="fine-tune")

# 2. Create fine-tuning job
job = client.fine_tuning.jobs.create(
    model="mistral-small-latest",
    training_files=[{"file_id": uploaded.id, "weight": 1}],
    hyperparameters={"training_steps": 10, "learning_rate": 0.0001},
)

# 3. Monitor
status = client.fine_tuning.jobs.get(job_id=job.id)

# 4. Use the fine-tuned model
response = client.chat.complete(
    model=job.fine_tuned_model,  # fine-tuned model ID
    messages=[{"role": "user", "content": "Hello"}],
)
```

Training data format (JSONL):
```json
{"messages": [{"role": "user", "content": "..."}, {"role": "assistant", "content": "..."}]}
```

Fine-tunable models: `mistral-small-latest`, `mistral-large-latest`, `codestral-latest`, `open-mistral-nemo`, `ministral-8b-latest`, `ministral-3b-latest`.

---

## Batch API

For large-volume offline workloads (up to 1M requests).

```python
# Inline mode (< 10k requests)
batch = client.batch.jobs.create(
    model="mistral-large-latest",
    endpoint="/v1/chat/completions",
    requests=[
        {"custom_id": "req-1", "body": {"messages": [{"role": "user", "content": "Hi"}]}},
        {"custom_id": "req-2", "body": {"messages": [{"role": "user", "content": "Bye"}]}},
    ],
)

# File-based mode (10k+ requests) -- upload JSONL first
```

---

## OpenAI SDK Compatibility

Mistral's API is compatible with the OpenAI Chat Completions format. You can use the OpenAI SDK:

```python
from openai import OpenAI

client = OpenAI(
    api_key=os.environ["MISTRAL_API_KEY"],
    base_url="https://api.mistral.ai/v1",
)

response = client.chat.completions.create(
    model="mistral-large-latest",
    messages=[{"role": "user", "content": "Hello!"}],
)
```

```typescript
import OpenAI from "openai";

const client = new OpenAI({
  apiKey: process.env.MISTRAL_API_KEY,
  baseURL: "https://api.mistral.ai/v1",
});
```

This works with LangChain, LlamaIndex, and other OpenAI-compatible frameworks.

### Key Differences from OpenAI

- `tool_choice: "any"` is Mistral's equivalent of OpenAI's `"required"`
- `safe_prompt` (boolean) replaces a separate moderation endpoint
- `parallel_tool_calls` is an explicit boolean parameter
- Dedicated FIM endpoint at `/v1/fim/completions` (no OpenAI equivalent)
- `prompt_mode: "reasoning"` for Magistral (no OpenAI equivalent)
- `prediction` parameter for speculative output (no OpenAI equivalent)

---

## Error Handling

| HTTP Code | Meaning | Action |
|-----------|---------|--------|
| 401 | Unauthorized | Check API key |
| 429 | Rate limited | Retry after `Retry-After` header delay |
| 500 | Server error | Retry with exponential backoff |

The Python SDK has built-in retry with configurable `RetryConfig`:

```python
from mistralai import Mistral
from mistralai.utils import BackoffStrategy, RetryConfig

client = Mistral(
    api_key=os.environ["MISTRAL_API_KEY"],
    retry_config=RetryConfig(
        strategy="backoff",
        backoff=BackoffStrategy(
            initial_interval=500,
            max_interval=60000,
            max_elapsed_time=300000,
            exponent=1.5,
        ),
    ),
)
```

---

## Rate Limits

- Set at the **workspace level**, determined by usage tier
- Two dimensions: **requests per second (RPS)** and **tokens per minute/month**
- Check your limits at [admin.mistral.ai/plateforme/limits](https://admin.mistral.ai/plateforme/limits)
- Use the Batch API for large-volume workloads to avoid rate limits

---

## SDK Method Reference

### Python (`mistralai` package, v1.12+, Python >= 3.10)

| Resource | Methods |
|----------|---------|
| `client.chat` | `.complete()`, `.stream()`, `.complete_async()`, `.stream_async()`, `.parse()` |
| `client.embeddings` | `.create()` |
| `client.fim` | `.complete()`, `.stream()` |
| `client.files` | `.upload()`, `.list()`, `.download()`, `.delete()` |
| `client.models` | `.list()`, `.delete()` |
| `client.fine_tuning.jobs` | `.create()`, `.list()`, `.get()`, `.start()`, `.cancel()` |
| `client.batch.jobs` | `.create()`, `.list()`, `.get()`, `.cancel()` |
| `client.beta.agents` | `.create()`, `.complete()`, `.stream()` |
| `client.beta.conversations` | `.start()`, `.append()` |
| `client.ocr` | `.process()` |

### TypeScript (`@mistralai/mistralai` package)

Same structure: `client.chat.complete()`, `client.chat.stream()`, `client.embeddings.create()`, `client.fim.complete()`, `client.files.*`, `client.models.*`, `client.fineTuning.jobs.*`, `client.batch.jobs.*`, `client.beta.agents.*`, `client.beta.conversations.*`, etc.

### Platform SDKs

- Azure: `pip install mistralai-azure` / `npm add @mistralai/mistralai-azure`
- GCP: `pip install mistralai-gcp` / `npm add @mistralai/mistralai-gcp`

---

## References

- [Documentation](https://docs.mistral.ai/)
- [Models Overview](https://docs.mistral.ai/getting-started/models/models_overview/)
- [API Reference](https://docs.mistral.ai/api/)
- [Python SDK](https://github.com/mistralai/client-python)
- [TypeScript SDK](https://github.com/mistralai/client-ts)
- [Pricing](https://mistral.ai/pricing)
- [Changelog](https://docs.mistral.ai/getting-started/changelog)
