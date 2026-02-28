# ImageElementStudio

Simple macOS SwiftUI app with:

- macOS menu-bar commands: new project, upload, analyze, save project, export JSON, build target
- Left pane: project progress and notes
- Middle pane: original design vs app emulator preview, builder chat
- Right pane: project memory, artboards, elements, and edit controls
- Idea-first mode: describe the app in chat (or menu command) to auto-generate wireframe artboards + scope + states

## Run

```bash
cd /Users/luke/ImageElementStudio
swift run
```

## Open in Xcode

1. Open Xcode.
2. Choose **File > Open**.
3. Select `/Users/luke/ImageElementStudio`.
4. Run the `ImageElementStudio` scheme.

## Current Analysis Behavior

- Text blocks from Vision OCR
- Rectangle candidates from Vision rectangle detection
- Semantic role mapping (navigation, KPI, chart, table, CTA, etc.)
- Product scope inference (app type, intent, capabilities, roadmap)
- Mirror blueprint inference (controls, states, suggested artboards, mirror score)
- Auto-generated state artboards from a single screenshot
- Idea-to-wireframe generation (no design file required)
- Project-scoped memory snapshots at `~/Library/Application Support/ImageElementStudio/projects/<project-id>/project-memory.json`
- Automatic snapshots whenever artboards are added, duplicated, removed, reset, or analyzed
- Clear memory action in menu and sidebar (`Clear Project Memory` / `Clear Memory`)
- Structured JSON export/edit loop from the active artboard
- Build setup output now includes starter scaffold files for iOS, macOS, and Web targets
- Build setup now also emits `full-app/` runnable app bundles per selected target
- Full-stack runs now emit one deterministic bundle for all targets (`web`, `ios`, `macos`) under a single timestamped run folder
- Generated full apps now include state transitions, control actions, capability cards, and activity logs
- Generated full apps are now multi-screen by default with state/artboard-driven navigation panels
- Each full app target now includes `app-spec.json` with inferred states, controls, capabilities, and transitions
- Full-stack runs emit `full-stack-summary.json` with per-target pass/fail, smoke/full-app pass rates, and aggregate score
- Full-stack runs also emit `run-full-app-checks.sh` for CI-style revalidation of generated web/iOS/macOS outputs
- Full-stack runs emit `enterprise-readiness-report.json` with weighted checks, blockers, and recommended actions
- Realtime build mode: auto-analyze imports and continuously refresh scaffold output
- Pro editing core: multi-select, marquee selection, distribute/space, resize/rotate handles, and keyboard shortcuts
- Pro editing benchmark runner with history, pass-rate trend chart, median latency tracking, and auto-fix/re-run support
- Benchmark trend direction indicator (improving/stable/regressing) and per-run median latency preview
- Standalone benchmark trend artifact exported on each build run (`benchmark-trend-report.json`)
- Smoke checks now validate full-app bundles and full-app `app-spec.json` integrity
- Component system: component creation, instances, variant axes/state mapping, and instance overrides
- Token revision history with rollback and global token propagation
- Interop fidelity diagnostics: structured import style mapping + import loss report
- Production quality artifacts: deterministic manifest hash, smoke checks, design-code diff report, and deterministic snapshot tests
- Collaboration flow: review comments + approval states, plus approval gate blocking build/interop export until approved
- Review panel now supports resolve/reopen/delete comments and bulk resolve/clear actions
- Review comments support assignee + due date metadata with overdue highlighting
- CI-style quality gate summary combines smoke checks, drift diffs, benchmark trend, and review gate into one score

## New Menus

- `Edit Layout`: nudge/fine nudge, rotate, distribute, run pro editing benchmark
- `Components`: create component, create instance, export interop package
- `Review`: pending/approved/changes-requested states

## Optional OpenAI Vision Enrichment

Set an API key before launch to enable remote multimodal interpretation:

```bash
export OPENAI_API_KEY="your_key_here"
cd /Users/luke/ImageElementStudio
swift run
```

## Supported Imports

- Raster: PNG, JPG/JPEG, HEIC, TIFF, GIF (plus any format NSImage can read)
- Design/vector: PDF, AI, EPS, SVG (via QuickLook fallback when needed)
- Structured: FIG/JSON where node geometry is readable (imports layers as elements)

If a proprietary design file cannot be parsed directly, export from Figma/Illustrator as PNG/PDF/SVG for best mirror fidelity.

## Docs

- Workflow and memory details: `docs/STUDIO_WORKFLOW.md`
