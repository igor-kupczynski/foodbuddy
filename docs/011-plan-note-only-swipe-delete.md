# Plan 011: Note-Only AI Analysis and Swipe Deletion

Status: Completed on 2026-02-19.

## Goal

- Allow creating a meal with notes only (no photo) and run AI food analysis on it.
- Allow deleting meals via right-to-left destructive swipe in History.
- Allow deleting food items via right-to-left destructive swipe in meal/day DQS lists.
- Ensure daily DQS updates immediately after these create/delete operations.

## Approach

- Extend analysis pipeline to accept text-only input when no images are present.
- Add a lightweight note-only meal entry flow that creates a meal record without entries and queues AI analysis.
- Add service-level meal deletion API that also removes local image files before deleting persisted records.
- Add `swipeActions` destructive controls in History/Meal Detail/Daily DQS views.
- Add/adjust unit tests for note-only analysis and deletion behavior.

## Tasks

- [Completed] T1: Add note-only meal creation path and allow AI analyze with notes but no images.
- [Completed] T2: Add meal swipe delete in History with file cleanup + persistence updates.
- [Completed] T3: Add food-item swipe delete in Meal Detail and Daily DQS views.
- [Completed] T4: Add/adjust tests for new behavior and run verifier commands.
- [Completed] T5: Update docs (`README.md`, `AGENTS.md`) with relevant behavior/lessons.

## Acceptance Criteria

- User can add a meal without photos by entering meal type + notes; if API key is configured it is analyzed.
- Mistral request works for notes-only input and does not require images.
- Swiping a meal row in History reveals destructive delete and removes meal + associated image files.
- Swiping a food item row reveals destructive delete and removes item from the list.
- Daily DQS totals/breakdowns update after note-only analysis, meal delete, and food-item delete.
- Automated tests covering new behavior pass.
