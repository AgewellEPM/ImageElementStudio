# ImageElementStudio Workflow

This document explains the menu-bar workflow, memory isolation, and save/export behavior.

## Menu Bar Actions

Top macOS menu bar actions are available across the whole app:

- `New`: creates a fresh project context with isolated memory.
- `Upload`: imports a design file (PNG/JPG/PDF/AI/SVG/FIG/JSON).
- `Analyze`: runs OCR + semantic + blueprint inference.
- `Generate Wireframes From Idea`: creates first-pass wireframes and scope from text only.
- `Save Project`: saves a full project package JSON.
- `Export JSON`: exports active analysis JSON only.
- `Clear Project Memory`: clears snapshots/notes for active project.
- `Build`: generates target build setup (iOS/macOS/Web).

## Project Memory Model

Memory is project-scoped and persisted per project ID:

- Path: `~/Library/Application Support/ImageElementStudio/projects/<project-id>/project-memory.json`
- Each project has independent snapshots, scope, and working hypothesis.
- Creating a `New` project creates a new project identity and fresh memory file.
- Switching projects resets workspace UI context to avoid stale notes from other projects.

Snapshot de-duplication is enabled to reduce repeated entries caused by rapid realtime re-analysis.
`Clear` in the center canvas no longer creates a memory snapshot.

## Save Project vs Export JSON

- `Save Project`:
  - Saves full studio state for the current project.
  - Includes artboards, selected artboard, memory, scope, blueprint, and current analysis document.
- `Export JSON`:
  - Saves only the currently active analysis document payload.

## Realtime Build Behavior

- Realtime build can auto-run analysis after imports.
- Realtime scaffold output is written to:
  - `~/Documents/ImageElementStudioBuilds/<project-slug>/realtime-<target>/`
- Manual build setup creates timestamped folders.

## Recommended Flow

1. Create a new project from menu `New`.
2. If you only have an idea, use `Generate Wireframes From Idea` or describe the idea in Builder Chat.
3. Review app emulator wireframes and refine scope/states.
4. Upload reference designs later for fidelity improvements (optional).
5. Save project package for checkpointing.
6. Export JSON or run Build target scaffolding.
