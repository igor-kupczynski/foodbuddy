# Mistral API — Operational Guide

Companion to [SKILL.md](SKILL.md). Covers production operational concerns: timeouts, streaming internals, vision optimization, and observability.

---

## Timeout & Cancellation Troubleshooting

| Symptom | Likely Cause | Actions |
|---------|--------------|---------|
| Connection reset / empty response after ~90-120s | Gateway timeout on non-streaming request | Switch to `stream: true`; reduce `max_tokens`; use a faster model (`mistral-small-latest`) for diagnosis |
| Truncated JSON in structured output | Token limit hit before schema completion | Increase `max_tokens`; simplify schema; shorten prompt |
| Slow first token on vision requests | Large image payload processing | Resize images before encoding; reduce image count; try URL instead of base64 |
| Intermittent 500 errors under load | Rate limiting or transient server errors | Enable SDK retry with exponential backoff (see SKILL.md Error Handling) |

### Debugging Checklist

When a request fails silently or takes unexpectedly long:

1. **Check if streaming is enabled** — non-streaming requests are held open until completion and are vulnerable to gateway timeouts.
2. **Check `max_tokens`** — high values on complex prompts extend generation time.
3. **Check image payload** — large base64 images add to both upload time and processing time.
4. **Try a faster model** — use `mistral-small-latest` to isolate whether the issue is model speed vs. network/timeout.
5. **Check `finish_reason`** — `"length"` means the output was truncated by `max_tokens`; `"stop"` means normal completion.

---

## Raw Streaming Patterns (Without SDK)

The Mistral SDKs handle SSE parsing internally. Use these patterns only if you're making raw HTTP requests.

### SSE Event Format

```
data: {"id":"...","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

data: {"id":"...","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}

data: {"id":"...","choices":[{"index":0,"delta":{"content":""},"finish_reason":"stop"}],"usage":{...}}

data: [DONE]
```

### Implementation Expectations

1. **Parse SSE events** — each line starting with `data: ` is a separate event. Blank lines separate events.
2. **Handle `data: [DONE]`** — this is NOT valid JSON. Check for it before parsing.
3. **Reassemble content** — concatenate `delta.content` from each chunk to build the full response.
4. **Extract usage** — token counts appear in the final chunk (before `[DONE]`), in the `usage` field.
5. **Handle connection drops** — implement reconnection logic; partial output is still usable up to the last received chunk.

### Pseudocode

```
buffer = ""
for line in sse_stream:
    if line == "data: [DONE]":
        break
    if line.startswith("data: "):
        chunk = json.parse(line[6:])
        delta = chunk.choices[0].delta.content
        if delta:
            buffer += delta
        if chunk.usage:
            token_counts = chunk.usage
# buffer now contains the full assistant response
```

---

## Vision Request Optimization

### Image Sizing

- **Resize before encoding** — sending a 4000x3000 photo when 1024x768 suffices wastes bandwidth and increases processing time.
- **Aim for the minimum resolution that preserves the information you need** — for text extraction, ~150 DPI is usually sufficient; for general scene understanding, 512-1024px on the long edge works well.

### Image Count

- Each additional image increases latency roughly linearly.
- **Keep image count low when debugging latency issues** — start with 1 image to establish a baseline.
- Maximum: 8 images per request, 10 MB per image.

### URL vs Base64

| Factor | URL | Base64 |
|--------|-----|--------|
| Payload size | Small (just the URL string) | Large (image bytes encoded at ~33% overhead) |
| Upload time | Fast | Slower for large images |
| Accessibility | Image must be publicly reachable by Mistral servers | Self-contained, no external access needed |
| Reliability | Depends on image host uptime | Always available once sent |
| Privacy | Image is fetched by Mistral servers | Image is sent inline, no external fetch |

**Recommendation**: Use URLs for publicly available images. Use base64 for private images or when you need guaranteed availability.

---

## Observability Checklist

Log the following for every Mistral API request (redact sensitive content):

| Field | Source | Why |
|-------|--------|-----|
| `model` | Request parameter | Track which model version is being used |
| Request payload size (bytes) | Serialized request body | Detect unexpectedly large payloads (especially base64 images) |
| Image count and dimensions | Request construction | Correlate with latency |
| `max_tokens` | Request parameter | Detect under/over-provisioned output budgets |
| `stream` | Request parameter | Distinguish timeout-vulnerable (false) from safe (true) requests |
| Time to first chunk | Timer from request send to first SSE event / response | Measures model queue + prompt processing time |
| Total latency | Timer from request send to completion | End-to-end request duration |
| HTTP status | Response | Detect errors, rate limits (429), server issues (500) |
| `finish_reason` | `response.choices[0].finish_reason` | `"length"` = truncated, `"stop"` = normal, `"tool_calls"` = tool use |
| `usage.prompt_tokens` | Response | Track input cost and context window consumption |
| `usage.completion_tokens` | Response | Track output cost and detect runaway generation |
| Request ID | `x-request-id` response header | Reference for Mistral support tickets |
