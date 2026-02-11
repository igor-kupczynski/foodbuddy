# FoodBuddy Iteration 009 — Fix Mistral Model ID

## Status: Complete

## Problem

Food photo analysis fails with HTTP 400:

```
"Invalid model: mistral-large-3-25-12"
```

## Root Cause

The model ID `mistral-large-3-25-12` is the **URL slug** on the Mistral docs site, not the actual API model identifier. The real API ID is `mistral-large-2512`. The incorrect ID was sourced from the `.claude/skills/mistral/SKILL.md` model tables, which use the slug instead of the API ID.

## Fix

Switch the model constant from the invalid pinned ID to the `mistral-large-latest` alias. This alias always resolves to the current Mistral Large model, preventing future breakage when Mistral retires or renames versions.

### Files Changed

| File | Change |
|------|--------|
| `FoodBuddy/Services/MistralFoodRecognitionService.swift` | Model constant → `mistral-large-latest` |
| `FoodBuddyCoreTests/MistralFoodRecognitionServiceTests.swift` | Test assertion → `mistral-large-latest` |
| `docs/007-plan-ai-food-recognition.md` | Updated model ID references |

### Note

The `.claude/skills/mistral/SKILL.md` also needs its model ID tables corrected (pinned IDs use URL slugs instead of actual API IDs). That update is tracked separately.
