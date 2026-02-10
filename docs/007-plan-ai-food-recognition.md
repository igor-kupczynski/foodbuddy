# FoodBuddy Iteration 007 Plan (AI Food Recognition + Batch Capture)

## 1. Goal

Add AI-powered food recognition to meal photos and introduce batch capture so users can photograph multiple dishes in one session.

After this iteration:
- Users capture one or more photos per meal in a single session
- Each meal gets an automatic AI-generated description of the food visible across all its photos
- Users can add optional notes (e.g. "Pizza Hut, double cheese upgrade") and re-analyze for a better description
- The capture flow stays fast — AI runs in the background after save

## 2. Context

### Why not Apple Intelligence

Apple provides no developer-facing VLM API. Visual Intelligence is user-facing only. Core ML can classify food into categories ("pizza") but cannot produce rich natural-language descriptions. A cloud VLM is required.

### AI provider

**Mistral Large 3** (`mistral-large-3-25-12`) — 675B sparse MoE model (41B active parameters) with native vision encoder. Supports multiple images per request, base64 image input, and enforced JSON schema output.

- API: `POST https://api.mistral.ai/v1/chat/completions`
- Auth: `Authorization: Bearer $MISTRAL_API_KEY`
- Images: base64-encoded JPEG in `image_url` content blocks using data URIs (`data:image/jpeg;base64,{base64data}`)
- Pricing: $0.50/M input tokens, $1.50/M output tokens
- Limits: 10 MB per image, max 8 images per request. Rate limits are workspace-tier dependent (check console.mistral.ai).

**Why Large 3 and not Small 3.2?** Mistral Small 3.2 (`mistral-small-latest`, 24B) also supports vision at $0.10/$0.30 per M tokens — 5x cheaper. For a 1-3 sentence food description, Small 3.2 may suffice. We start with Large 3 for quality and can downgrade to Small 3.2 later if costs matter and quality is acceptable. The service protocol abstracts the model choice, so switching is a one-line change.

## 3. Product Outcomes

- Batch capture: user takes 1-N photos, picks meal type once, saves all entries to one meal.
- AI description appears on meal detail and as a preview in the history list.
- Optional notes field at capture time (also editable later in meal detail).
- Re-analyze button sends photos + updated notes back to the VLM.
- Graceful degradation: no API key → everything works, just no AI descriptions.

## 4. Key Design Decisions

### Capture flow — batch session replacing CaptureMealTypeSheet

Current flow uses `CaptureMealTypeSheet` — a sheet showing one photo + meal type picker. The new `CaptureSessionView` replaces it with a richer review screen that supports multiple photos.

Current: `tap [+] → source dialog → camera → CaptureMealTypeSheet(1 photo) → Save`

New:

```
tap [+] → source dialog → camera → CaptureSessionView(1 photo in gallery)
                                      ├── [Add photo] → source dialog → camera → returns with 2 photos
                                      ├── [Add photo] → ... → returns with N photos
                                      ├── Notes text field (optional)
                                      ├── Meal type picker (time-based default)
                                      └── [Save]
```

The `CaptureSessionView` is presented as a `.sheet` (same as current `CaptureMealTypeSheet`). When the user taps "Add photo", it opens a source dialog and then a `.fullScreenCover` for the camera/library *from within* the sheet. The photo is appended to the gallery and the user returns to the session view.

For the **single-photo case** (most common), the experience is nearly identical to today — one extra "Add photo" button is visible but ignorable.

### CaptureSessionView layout

```
┌─ NavigationStack ──────────────────┐
│  [Cancel]      Save Meal    [Save] │
├────────────────────────────────────┤
│                                    │
│  ┌──────────────────────────────┐  │
│  │                              │  │
│  │         Photo 1        [✕]  │  │
│  │                              │  │
│  └──────────────────────────────┘  │
│  ┌──────────────────────────────┐  │
│  │                              │  │
│  │         Photo 2        [✕]  │  │
│  │                              │  │
│  └──────────────────────────────┘  │
│                                    │
│        [+ Add another photo]       │
│                                    │
│  ┌──────────────────────────────┐  │
│  │ Any details? (optional)      │  │
│  └──────────────────────────────┘  │
│                                    │
│  Meal Type: [Lunch           ▾]   │
│  12:34 PM, Feb 10, 2026           │
│                                    │
└────────────────────────────────────┘
```

- Scrollable `Form` or `List` with photo cards (aspect-fit, rounded corners, ✕ to remove)
- Save is disabled when gallery is empty
- Removing the last photo doesn't dismiss — user can add a new one or tap Cancel

### AI description scope

**Per-meal, not per-photo.** All photos for a meal are sent in one VLM call. The model sees the full context and produces one coherent description.

### Notes scope

**One notes field per meal**, not per photo. Stored on `Meal`. Sent alongside images in the VLM request.

### When AI runs

**Automatic after save**, if an API key is configured. No manual trigger needed for first analysis. Re-analysis is always manual (user taps re-analyze in meal detail).

### Error handling — no auto-retry

If the API call fails, the meal's status is set to `failed`. The UI shows this clearly. The user can manually retry via the same re-analyze button used for notes changes. No background retry logic, no exponential backoff — keep it simple.

Mistral API error codes to handle: 401 (bad API key — surface to user in Settings), 429 (rate limited — treat as transient failure), 5xx (server error — transient failure). All map to the same `failed` status; the user-facing message can vary.

### Where AI description appears

**History list (MealRowView)** — 1-line preview under the meal type name, replacing the entry count line when a description exists:

```
┌──────────────────────────────────┐
│ [thumb]  Lunch                   │
│          Margherita pizza with…  │
│          Feb 10 • 12:30-12:35   │
└──────────────────────────────────┘
```

**Meal detail (MealDetailView)** — description section at the top, above the entries list:

```
┌──────────────────────────────────┐
│ AI Description                   │
│ ┌──────────────────────────────┐ │
│ │ Margherita pizza with double │ │
│ │ cheese and a side Caesar     │ │
│ │ salad with sparkling water.  │ │
│ └──────────────────────────────┘ │
│                                  │
│ Notes                            │
│ ┌──────────────────────────────┐ │
│ │ Pizza Hut, double cheese     │ │
│ └──────────────────────────────┘ │
│ [Re-analyze]                     │
├──────────────────────────────────┤
│ Entry 1 row                      │
│ Entry 2 row                      │
│ ...                              │
└──────────────────────────────────┘
```

**States in meal detail:**
- `none` — no API key configured. Show subtle text: "Set up AI in Settings to get meal descriptions."
- `pending` / `analyzing` — spinner + "Analyzing…"
- `completed` — description text + notes field + re-analyze button
- `failed` — "Analysis failed" message + re-analyze button to retry

## 5. AI Prompt and Response Schema

### System prompt

```
You are a food-logging assistant. The user sends photos from a single
meal, possibly with notes for context.

- Describe all food and drink items visible across the photos
- If a photo shows a nutrition label or restaurant menu, extract the
  relevant items and nutritional info instead of describing the image
- Incorporate the user's notes — they may correct, clarify, or add
  context the photos don't show
- Be concise and specific (e.g. "grilled chicken breast" not just "meat")
```

### User message

```
[image_1] [image_2] ... [image_n]
(if notes provided) "Additional context: {user_notes}"
```

Images are sent as content blocks with `type: "image_url"` and base64-encoded JPEG data URIs:

```json
{
  "type": "image_url",
  "image_url": "data:image/jpeg;base64,/9j/4AAQ..."
}
```

### Enforced JSON schema via `response_format`

Mistral supports strict schema enforcement through the `response_format` parameter — the model is constrained to output valid JSON matching the schema. No need to hope it follows instructions.

```json
{
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "name": "food_description",
      "strict": true,
      "schema": {
        "type": "object",
        "properties": {
          "description": {
            "type": "string",
            "description": "1-3 sentence description of the food and drink items in the meal"
          }
        },
        "required": ["description"],
        "additionalProperties": false
      }
    }
  }
}
```

This guarantees we always get `{"description": "..."}` back — no parsing surprises.

## 6. Data Model Changes

### On `Meal` — new fields

```
aiDescription: String?       — AI-generated meal description
userNotes: String?           — user-provided hints/context
aiAnalysisStatus: String     — "none" | "pending" | "analyzing" | "completed" | "failed"
```

These are string fields on an existing SwiftData model — CloudKit sync comes for free.

`aiAnalysisStatus` defaults to `"none"` for existing meals and `"pending"` for new meals when an API key is configured.

## 7. Service Architecture

### FoodRecognitionService (protocol)

```swift
protocol FoodRecognitionService {
    func describe(images: [Data], notes: String?) async throws -> String
}
```

Takes JPEG data for all meal photos + optional notes. Returns the description string.

### MistralFoodRecognitionService

This is the first REST API client in the app (existing networking is CloudKit only). Uses `URLSession` directly — no SDK needed since Mistral's API is a single endpoint.

- Builds multipart content blocks: base64 `image_url` blocks + optional text block for notes
- Sends `POST /v1/chat/completions` with system prompt + `response_format` (json_schema, strict)
- Decodes JSON response → `choices[0].message.content` → parses inner `{"description": "..."}` string
- Throws typed errors: `networkError`, `httpError(statusCode)`, `decodingError`, `noAPIKey`
- Uses pinned model ID (`mistral-large-3-25-12`) for production stability, not `-latest` alias

### MockFoodRecognitionService

Returns canned responses. Used in previews and tests.

### FoodAnalysisCoordinator

- On app foreground + after new capture: queries meals with `aiAnalysisStatus == "pending"`
- Sets status to `"analyzing"`, loads all entry images from `ImageStore`
- Calls `FoodRecognitionService.describe(...)`
- On success: writes description, sets status to `"completed"`
- On failure: sets status to `"failed"` — no auto-retry

Re-analyze (from meal detail) also goes through this coordinator: resets status to `"pending"`, coordinator picks it up.

### API Key Storage

- New Settings screen accessible from History view
- Text field for Mistral API key
- Stored in iOS Keychain (not UserDefaults)
- Coordinator checks for key presence before attempting analysis

## 8. Milestones

### M1: Batch capture session

- New `CaptureSessionView` replacing `CaptureMealTypeSheet`
- Scrollable photo gallery with add/remove
- Notes text field + meal type picker
- "Add photo" opens source dialog → camera/library from within the sheet
- Creates multiple `MealEntry` records in one meal on save
- Single-photo case works naturally (gallery with 1 photo)

### M2: Data model + service layer

- Add `aiDescription`, `userNotes`, `aiAnalysisStatus` to `Meal`
- `FoodRecognitionService` protocol + `MistralFoodRecognitionService`
- `MockFoodRecognitionService` for tests
- `FoodAnalysisCoordinator` background worker (no auto-retry)
- Keychain wrapper for API key storage

### M3: Settings screen

- API key input + Keychain persistence
- Accessible from History view

### M4: AI description display + re-analyze

- MealDetailView: description section, notes editing, re-analyze button, all status states
- MealRowView: 1-line description preview
- Re-analyze = set status to pending → coordinator picks up

### M5: Verification + docs

- Unit tests: mock service, coordinator writes descriptions, failure sets status
- UI test: batch capture flow with mock camera
- Manual: capture meal → wait for description → edit notes → re-analyze
- Update README.md

## 9. Automated Validation Gates

Each milestone has a set of checks the implementing agent **must** pass before moving on. All gates run without a real Mistral API key and without an iOS Simulator.

### Build + existing tests (every milestone)

```bash
# Regenerate project after any project.yml change
xcodegen generate

# Build the main app target (iOS)
xcodebuild build -project FoodBuddy.xcodeproj -scheme FoodBuddy \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO | xcbeautify

# Run core unit tests (macOS, no simulator)
xcodebuild test -project FoodBuddy.xcodeproj -scheme FoodBuddy \
  -destination 'platform=macOS' | xcbeautify

# Launch screen guardrail
./scripts/assert-launch-screen-config.sh
```

All four commands must exit 0. Existing tests must keep passing — no regressions.

### M1 gate: Batch capture session

New tests in `FoodBuddyCoreTests` (follow existing `TestHarness` pattern with in-memory SwiftData):

- **Batch save creates multiple entries**: Save a session with 3 photos → meal has 3 `MealEntry` records, all sharing the same `Meal`.
- **Single-photo save still works**: Save with 1 photo → identical to current behavior (1 meal, 1 entry).
- **Empty gallery cannot save**: Verify save is blocked when photo array is empty.

### M2 gate: Data model + service layer

New tests in `FoodBuddyCoreTests`:

- **Meal model has new fields**: Create a `Meal`, set `aiDescription`, `userNotes`, `aiAnalysisStatus` → persists and round-trips through in-memory SwiftData.
- **MistralFoodRecognitionService builds correct request JSON**: Inject a mock `URLProtocol` that captures the outgoing `URLRequest`. Call `describe(images:notes:)` with 2 JPEG blobs + a note string. Assert:
  - URL is `https://api.mistral.ai/v1/chat/completions`
  - `Authorization` header is `Bearer <key>`
  - Body JSON contains `model: "mistral-large-3-25-12"`
  - `messages[0].role == "system"` with the food-logging prompt
  - `messages[1].content` array has 2 `image_url` blocks + 1 text block with `"Additional context: ..."`
  - `response_format.json_schema.strict == true`
- **MistralFoodRecognitionService parses response**: Feed a canned `{"choices":[{"message":{"content":"{\"description\":\"Grilled salmon with rice\"}"}}]}` response through the mock URLProtocol → service returns `"Grilled salmon with rice"`.
- **MistralFoodRecognitionService handles errors**: 401 response → throws appropriate error. 500 response → throws appropriate error. Malformed JSON → throws decoding error.
- **FoodAnalysisCoordinator happy path**: With `MockFoodRecognitionService` returning a canned description: create a meal with `aiAnalysisStatus == "pending"` → run coordinator → status becomes `"completed"`, `aiDescription` is set.
- **FoodAnalysisCoordinator failure path**: Mock service throws → status becomes `"failed"`, `aiDescription` remains nil.
- **FoodAnalysisCoordinator skips without API key**: No key configured → pending meals stay pending, no service call made.

### M3 gate: Settings screen

- Build succeeds (covered by the base gate).
- **Keychain wrapper unit test**: Write a key → read it back → matches. Delete → read returns nil. (Use a test-specific service name to avoid polluting the real keychain.)

### M4 gate: AI description display + re-analyze

- Build succeeds (covered by the base gate).
- **Re-analyze resets status**: Set a meal's `aiAnalysisStatus` to `"completed"` → trigger re-analyze → status becomes `"pending"`.

### M5 gate: Final verification

- All gates above pass in a single clean run.
- `xcodegen generate && xcodebuild build` succeeds for `FoodBuddyDev` scheme too.

## 10. Risks and Mitigations

- **Risk**: Image token cost spikes with many large photos.
  - Mitigation: Images already preprocessed to max 1600px / 75% JPEG. Max 8 images per API call matches Mistral limit.
- **Risk**: Batch capture state complexity (multiple photos, source dialogs within sheets).
  - Mitigation: Build on existing capture patterns. Gallery is a simple `[PlatformImage]` array.
- **Risk**: API key exposure in device backups.
  - Mitigation: Keychain storage (excluded from unencrypted backups by default).

## 11. Execution Status

Last updated: 2026-02-10

- M1 Batch capture session: `Not started`
- M2 Data model + service layer: `Not started`
- M3 Settings screen: `Not started`
- M4 AI description display + re-analyze: `Not started`
- M5 Verification + docs: `Not started`
