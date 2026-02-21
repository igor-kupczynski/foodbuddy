# Plan 015: Mistral Long-Running Request Reliability (App + Evals Parity)

Status: In Progress on 2026-02-21 (implementation complete; blocked on upstream URLSession HTTP/3 path instability for image requests).

## Goal

- Prevent `case-001` (image-based eval) failures caused by long-running non-streaming requests ending before completion.
- Keep transport behavior aligned between app and evals (same Mistral endpoint family, same request strategy, no curl transport split).

## Research Summary (Official Mistral Docs)

- `POST /v1/chat/completions` supports a `stream` request flag and `text/event-stream` responses.
- With `stream=false`, the server holds the request open until completion or timeout.
- Mistral completion docs note non-streaming latency grows with longer outputs.
- Batch API is designed for high-throughput / low-latency-insensitive work (async), not low-latency interactive usage.

Implication:
- The observed ~116s cancellation for `case-001` is consistent with a long-held non-streaming request hitting an upstream timeout boundary before full completion.
- To preserve app/eval parity for interactive analysis, chat-completions streaming is the best first fix.

## Approach

### A. Add shared streaming support (primary fix)

- Extend `FoodBuddyAIShared` request builder to support `stream: true` mode for chat completions.
- Implement SSE reader/parser for Mistral stream chunks (`URLSession.bytes(for:)`) that reconstructs assistant content text.
- Reuse the same final JSON parsing/validation path once full content is reconstructed.

### B. Keep app + eval behavior aligned

- Update app `MistralFoodRecognitionService` to use the shared streaming path.
- Update eval runner to use the same shared streaming path for case execution.
- Keep model defaults the same unless explicitly overridden by case/CLI.

### C. Add request-budget controls (secondary reliability)

- Add explicit `max_tokens` in shared request builder for this workload (bounded concise JSON output).
- Keep existing case/model override controls and document a faster-model fallback for debugging.

### D. Improve diagnostics (without transport divergence)

- Emit timing checkpoints in eval artifacts:
  - request body size
  - time to first stream chunk
  - total stream duration
  - stream completion marker received / not received
- Preserve existing URLSession error details and clear guidance in notes.

### E. Optional async mode for non-interactive bulk evals (deferred)

- Add separate eval mode using Batch API + polling only if needed for long offline suites.
- Keep this opt-in and separate from the app-parity default path.

## Tasks

- [x] T0: Draft local maintainer feedback note for Mistral skill gaps and improvements at `mistral-skill-update.local.md` (do not commit). `Completed`
- [x] T1: Add `stream` + optional `max_tokens` support to shared request types in `Packages/FoodBuddyAIShared`. `Completed`
- [x] T2: Add streaming response assembler/parser utilities in shared package with focused tests (chunk assembly, done marker, malformed event handling). `Completed`
- [x] T3: Switch app `MistralFoodRecognitionService` to shared streaming path; preserve error mapping semantics. `Completed`
- [x] T4: Switch eval runner to shared streaming path and add timing metrics to result artifact. `Completed`
- [x] T5: Add/adjust tests for app + shared package behavior parity and failure handling. `Completed`
- [x] T6: Update docs (`README.md`, `AGENTS.md`) for streaming-based parity behavior and troubleshooting guidance. `Completed`
- [x] T7: Run selective verification:
  - `cd Packages/FoodBuddyAIShared && swift test`
  - `cd evals && swift build`
  - `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'`
  `Completed`

## Acceptance Criteria

- `case-001` reliably completes via URLSession-only chat completions under the default workflow.
- App and eval use the same transport strategy (streaming chat completions, same shared parser path).
- No curl fallback path is reintroduced.
- Eval artifacts include enough timing detail to distinguish slow generation from transport failure.
- Selective verification commands pass.

## Verification Results (2026-02-21)

- `xcodegen generate` -> pass
- `cd Packages/FoodBuddyAIShared && swift test` -> pass
- `cd evals && swift build` -> pass
- `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'` -> pass
- `make eval-run` -> runs all cases; `case-002` passes, `case-001` still fails after retries with upstream HTML `502 Bad gateway` on image requests

## Investigation Update (2026-02-21)

- Built the same request shape (model, prompt, strict `response_format`, two case-001 images, `stream: true`, `max_tokens: 400`) and replayed it outside the eval runner.
- `curl` to `https://api.mistral.ai/v1/chat/completions` succeeds consistently (`HTTP/2 200`, SSE stream starts immediately; 5/5 successful runs).
- `URLSession` with the same body and headers fails (`HTTP 502` HTML Cloudflare page at ~15s, or timeout/cancel variants).
- `URLSessionTaskMetrics` for failing runs reports `networkProtocolName = h3` and Cloudflare IPv6 edge address `2606:4700::6812:1698`.
- Explicit request opt-outs (`assumesHTTP3Capable = false`, `allowsPersistentDNS = false`) did not prevent `h3` selection in tested runs.
- Conclusion: this is not a prompt/schema/body mismatch; failure is tied to URLSession + Cloudflare HTTP/3 transport path for this workload.

## Blocker

- `case-001` remains blocked by URLSession requests negotiating HTTP/3 (`h3`) to Cloudflare and returning `502`/timeout on image payloads, while equivalent `curl` HTTP/2 requests succeed.
- Current implementation captures bounded response previews, timing, request size, and retry attempts; additional task-metrics capture is needed to persist protocol-level evidence (`h2`/`h3`, remote address, cf-ray) directly in artifacts.
