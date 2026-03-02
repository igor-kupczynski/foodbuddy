# Plan 015: Mistral Long-Running Request Reliability (App + Evals Parity)

Status: In Progress on 2026-03-02 (app-side HTTP 429 handling plus AI payload-size controls implemented and verified with targeted core tests; physical iPhone validation still pending; eval URLSession parity remains blocked on HTTP/3 path instability).

## Goal

- Prevent `case-001` (image-based eval) failures caused by long-running non-streaming requests ending before completion.
- Keep transport behavior aligned between app and evals (same Mistral endpoint family, same request strategy, no curl transport split).
- Make app-side image analysis resilient to Mistral HTTP `429` rate limits, especially for photo-backed requests from physical iPhone runs.

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

### F. Add rate-limit-aware retry + requeue behavior (app-side follow-up)

- Extend the app transport contract so non-2xx responses can expose headers as well as status/body preview.
- When Mistral returns HTTP `429`, honor `Retry-After` if present; otherwise use a longer bounded exponential backoff with jitter than the current `0.5s -> 1s` sequence.
- If the final app attempt still ends in `429`, do not treat it like a permanent analysis failure. Requeue the meal for later retry (or persist a retry-after timestamp) instead of leaving it in terminal `.failed`.
- Preserve actionable diagnostics for the user/debugger: final status code, bounded response body, relevant retry headers, attempt count, and next eligible retry time.
- Expand the in-app error-details payload shown from `MealDetailView` so transient AI failures include transport/request telemetry that is useful on-device without Xcode attached.
  - request image count
  - total encoded request size in bytes
  - model ID
  - attempt count / max attempts
  - retry delays applied
  - parsed `Retry-After` value, if present
  - selected response headers worth inspecting for throttling/debugging (for example `retry-after`, `x-ratelimit-*`, `cf-ray`)
  - next eligible retry timestamp if the meal is requeued

### G. Reduce AI request payload size for photo analysis

- Keep local app photo quality and sync quality unchanged unless there is a separate product decision; optimize only the AI request payload.
- Add an AI-specific preprocessing step before request encoding so image bytes sent to Mistral are substantially smaller than the stored capture JPEGs.
- Target a clear byte budget:
  - log per-image byte size and total request body bytes
  - prefer a total request body comfortably below the current ~8.3 MB observed for 2-photo meals
- Validate that the request format stays compliant with Mistral vision chat completions:
  - `content` blocks with `type: "image_url"`
  - `image_url` as `data:image/jpeg;base64,...` is still allowed
- Confirmed from current Mistral docs:
  - Chat vision supports image URL and base64-encoded image input
  - the Files API documents purposes `fine-tune`, `batch`, and `ocr`; it does not document a chat-completions image-file reference flow
  - implication: current app image transport format is correct; payload reduction should focus on image bytes or moving to publicly hosted image URLs if that ever becomes feasible
- Evaluate two knobs first, in order:
  - smaller AI long-edge resize
  - lower AI JPEG quality
- Keep the first pass simple; do not add image-selection heuristics unless size reduction alone is insufficient.
- Add user-configurable AI image payload settings in AI Settings:
  - `long edge` with default `1024`
  - `quality` with default `75`
- Keep these settings clearly scoped to AI analysis payload generation, not local photo storage or photo sync.

### H. Future improvement: hosted image URLs instead of base64-embedded request bodies

- If we later add a secure hosted-image flow (for example time-bounded S3 object URLs), prefer passing image URLs to Mistral chat completions instead of embedding base64 image bytes in the JSON body.
- This should stay explicitly deferred until there is a product decision on where AI-analysis images may be uploaded and how long they may remain accessible.
- Treat this as an optimization path, not the immediate fix; AI-only resizing/compression remains the first-line payload reduction.

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
- [x] T8: Investigate physical-iPhone HTTP `429` failure for image + note analysis and determine whether it is request-shape, duplicate-trigger, or retry-policy related. `Completed 2026-03-02`
- [x] T9: Extend app `MistralHTTPTransport` / `MistralFoodRecognitionService` to surface response headers on non-2xx responses, parse `Retry-After`, and apply longer jittered backoff for `429`. `Completed 2026-03-02`
- [x] T10: Add app-level transient-rate-limit handling so exhausted `429` attempts requeue analysis instead of marking the meal permanently `.failed`. `Completed 2026-03-02`
- [x] T11: Expand coordinator/service diagnostics shown in the app error-details sheet to include request/transport telemetry for transient AI failures. `Completed 2026-03-02`
- [x] T12: Add focused tests covering `429` retry timing, `Retry-After` parsing, exhausted-rate-limit requeue semantics, and diagnostic-field population in `FoodBuddyCoreTests`. `Completed 2026-03-02`
- [ ] T13: Run selective verification for the app-side follow-up:
  - `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'`
  - manual physical iPhone validation: create a meal with 2 photos + notes, confirm no terminal `.failed` state on transient `429`
  `In Progress`
- [x] T14: Investigate AI request payload reduction and confirm current image transport format remains correct against Mistral vision docs. `Completed 2026-03-02`
- [x] T15: Add persisted AI payload settings (`long edge`, `quality`) and surface them in `AISettingsView` with defaults `1024` / `75`. `Completed 2026-03-02`
- [x] T16: Add AI-specific image downscaling/compression before Mistral request assembly, driven by those settings, plus telemetry for per-image/request byte sizes. `Completed 2026-03-02`
- [x] T17: Add focused tests for settings persistence, reduced-payload request building, and keep existing response parsing/retry behavior unchanged. `Completed 2026-03-02`
- [x] T18: Document deferred hosted-image optimization path (for example S3 pre-signed URLs) so future work can avoid base64 request bloat when privacy/product constraints allow it. `Completed 2026-03-02`

## Acceptance Criteria

- `case-001` reliably completes via URLSession-only chat completions under the default workflow.
- App and eval use the same transport strategy (streaming chat completions, same shared parser path).
- No curl fallback path is reintroduced.
- Eval artifacts include enough timing detail to distinguish slow generation from transport failure.
- Selective verification commands pass.
- On app-side `429`, the service waits long enough to respect server rate limiting instead of failing after ~1.5 seconds total backoff.
- If app-side retries are exhausted on `429`, the meal remains retryable and does not end in a misleading permanent failure state.
- Error details for rate-limited meals include enough header/body context to distinguish quota exhaustion from malformed requests.
- AI Settings exposes payload controls for Mistral analysis uploads (`long edge`, `quality`) without changing local photo storage or sync behavior.
- The active plan documents a future hosted-image URL path (for example S3 pre-signed URLs) as a deferred payload-optimization option.

## Verification Results (2026-02-21)

- `xcodegen generate` -> pass
- `cd Packages/FoodBuddyAIShared && swift test` -> pass
- `cd evals && swift build` -> pass
- `xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'` -> pass
- `make eval-run` -> runs all cases; `case-002` passes, `case-001` still fails after retries with upstream HTML `502 Bad gateway` on image requests

## Verification Results (2026-03-02)

- `xcodegen generate` -> pass
- `xcodebuild -quiet build -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` -> pass
- `xcodebuild -quiet build-for-testing -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64'` -> pass
- `xcodebuild test-without-building -project FoodBuddy.xcodeproj -scheme FoodBuddy -destination 'platform=macOS,arch=x86_64' -only-testing:FoodBuddyCoreTests/MistralAISettingsStoreTests -only-testing:FoodBuddyCoreTests/MistralFoodRecognitionServiceTests -only-testing:FoodBuddyCoreTests/FoodAnalysisCoordinatorTests` -> pass
- manual physical iPhone validation -> pending

## Investigation Update (2026-02-21)

- Built the same request shape (model, prompt, strict `response_format`, two case-001 images, `stream: true`, `max_tokens: 400`) and replayed it outside the eval runner.
- `curl` to `https://api.mistral.ai/v1/chat/completions` succeeds consistently (`HTTP/2 200`, SSE stream starts immediately; 5/5 successful runs).
- `URLSession` with the same body and headers fails (`HTTP 502` HTML Cloudflare page at ~15s, or timeout/cancel variants).
- `URLSessionTaskMetrics` for failing runs reports `networkProtocolName = h3` and Cloudflare IPv6 edge address `2606:4700::6812:1698`.
- Explicit request opt-outs (`assumesHTTP3Capable = false`, `allowsPersistentDNS = false`) did not prevent `h3` selection in tested runs.
- Conclusion: this is not a prompt/schema/body mismatch; failure is tied to URLSession + Cloudflare HTTP/3 transport path for this workload.

## Investigation Update (2026-03-02)

- Reproduced path from current app code inspection: physical iPhone save -> `HistoryView.saveCaptureSession()` -> `FoodAnalysisCoordinator.processPendingMeals()` -> `MistralFoodRecognitionService.analyze()`.
- The app is already on AsyncHTTPClient transport, so this specific failure is not the earlier URLSession HTTP/3 / Cloudflare `502` issue tracked above.
- The request shape looks valid for Mistral vision:
  - app capture flow allows up to 8 photos
  - images are preprocessed to JPEG with max long edge `1600`
  - the failing case uses 2 images + notes, which is within Mistral's published multimodal limits
- No clear duplicate-trigger bug was found in the current app flow:
  - `HistoryView` and `MealDetailView` each guard concurrent runs with `isRunningFoodAnalysis`
  - `FoodAnalysisCoordinator` is an actor and serializes `processPendingMeals()`
- Current `429` handling is too weak for real rate-limit windows:
  - `maxAttempts = 3`
  - backoff is only `500ms`, then `1000ms`
  - transport does not expose response headers, so the service cannot honor `Retry-After`
  - after the final `429`, coordinator marks the meal `.failed`
- Working conclusion: the likely root cause is genuine upstream rate limiting combined with insufficient app-side wait/requeue behavior, not malformed payload construction.

## Blocker

- `case-001` remains blocked by URLSession requests negotiating HTTP/3 (`h3`) to Cloudflare and returning `502`/timeout on image payloads, while equivalent `curl` HTTP/2 requests succeed.
- Current implementation captures bounded response previews, timing, request size, and retry attempts; additional task-metrics capture is needed to persist protocol-level evidence (`h2`/`h3`, remote address, cf-ray) directly in artifacts.
- Separately, the app currently lacks rate-limit-aware retry semantics for Mistral `429`; until T9-T12 land, transient quota throttling on physical iPhone runs can still end in terminal meal-analysis failure.
