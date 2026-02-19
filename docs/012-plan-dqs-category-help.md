# Plan 012: DQS Category and Portion Help UI

Status: Completed on 2026-02-19.

## Goal

- Add an in-app help reference that explains what foods belong to each DQS category and what counts as one serving.
- Make the help discoverable from food-item add/edit flows and daily DQS view.

## Approach

- Add reusable DQS category guide metadata in `DQSCategory` so category names, examples, and serving guidance are defined in one place.
- Build a reusable SwiftUI guide view/sheet that presents all categories with concise examples and serving-size guidance.
- Add help entry points where users need it most: Daily DQS toolbar and manual food item add/edit screens.
- Add UI test coverage for help discovery + key guide content visibility.

## Tasks

- [x] T1: Add category guide metadata to `DQSCategory` (food examples + serving guidance). `Completed`
- [x] T2: Build reusable `DQSCategoryGuideView` and present it as a sheet. `Completed`
- [x] T3: Add help triggers in `DailyDQSView`, `ManualFoodItemSheet`, and `FoodItemEditView`. `Completed`
- [x] T4: Add/adjust UI tests for help accessibility and key content. `Completed`
- [x] T5: Run verifier test/build commands and update docs (`README.md`, `AGENTS.md`) as needed. `Completed`

## Acceptance Criteria

- Users can open a DQS help sheet from Daily DQS and from food-item add/edit forms.
- Help sheet lists all DQS categories with practical example foods.
- Help sheet explains a basic “what is one serving” guide for each category.
- Copy is concise and usable while entering/editing food items.
- DQS UI tests pass with the new help entry points.
