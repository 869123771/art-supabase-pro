---
name: project-code-quality
description: Enforce repository-wide code quality for art-supabase-pro. Use before creating, modifying, refactoring, or reviewing any source code, API provider, shared utility, composable, store, test, Edge Function, or project structure. Covers reuse, module placement, error handling, type safety, duplicate-code removal, change isolation, and verification gates.
---

# Project Code Quality

Keep every change maintainable at repository scale, not merely functional in the edited file.

## Inspect Before Editing

1. Read `AGENTS.md`, the target module, related types, and the closest established implementation.
2. Run `git status --short`; preserve unrelated user changes.
3. Search with `rg` for existing utilities, dependencies, duplicated patterns, exports, imports, and tests before adding code.
4. Load additional domain skills required by the task. Supabase work must also use the local Supabase skill; user-facing frontend work must also use the frontend conventions and UI-quality skills.

## Keep One Clear Ownership Boundary

- Place code by technology and responsibility. Keep reusable Supabase helpers under `src/utils/supabase/`; do not scatter `supabase-*` utilities across `src/utils`.
- Keep transport logic in `src/api/**`, UI behavior in components/views, shared policy in `src/utils` or hooks, and domain-only policy beside its feature.
- Expose one canonical implementation. Remove obsolete files, duplicate local helpers, compatibility aliases, and stale imports after migrating callers.
- After changing repository structure or conventions, run `pnpm snapshot:ai` so the bundled AI project snapshot cannot recommend deleted paths or outdated rules.
- Extend the closest shared module when three or more callers need the same behavior, or when the behavior is cross-cutting policy such as error normalization.
- Do not create a wrapper that only renames an existing library or project utility.

## Reuse Before Creating

Follow this order:

1. Reuse an installed focused dependency.
2. Reuse an existing project utility or core component.
3. Extend the closest shared abstraction.
4. Add a new helper only when the behavior has a distinct reusable policy.

Do not hand-write generic parsing, object, collection, date, async, observer, or formatting behavior already provided by installed dependencies.

- Use focused collection/object helpers such as `uniq`, `uniqBy`, `omit`, `get`, and `cloneDeep` instead of repeating `Set`-based de-duplication, manual property deletion, dynamic indexing, or ad-hoc deep cloning.
- When repeated display formatting has one policy, give it one named shared helper; keep domain-specific normalization beside the domain rather than in a generic UI utility.

## Protect User-Facing Error Quality

- Never render or toast raw error objects, `JSON.stringify(error)`, `String(error)`, provider class names, stack traces, SQL text, or unexplained English SDK messages.
- Normalize Supabase Auth, PostgREST, Storage, and Edge Function failures in `src/utils/supabase/error.ts`.
- Branch on stable `code`, error class/name, or HTTP status before inspecting message text.
- Preserve concise Chinese business messages returned intentionally by the server. Replace unknown technical text with a workflow-specific Chinese fallback that explains the next action.
- Parse Edge Function response bodies in the API/shared boundary. Do not duplicate `normalizeFunctionInvokeError` helpers across providers.
- Keep raw errors available for diagnostics through causes, raw return fields, or controlled logs; do not expose them in the interface.
- Avoid duplicate notifications. Choose one owner—the shared response layer or the feature catch block—to display a failure.

## Enforce Semantic UI Quality

- Use native `button`, `a`, and router-link elements for actions and navigation. Do not attach actions to `div`, `span`, `li`, `p`, or `i`; ARIA roles are reserved for established composite widgets such as tabs.
- External links opened with `target="_blank"` must include `rel="noopener noreferrer"`; shared navigation helpers must enforce the same opener isolation.
- Icon-only actions require an accessible name, a visible keyboard focus state, and a tooltip or `title` when the meaning is not obvious.
- Upload controls must expose one interactive trigger. Generic attachments use `ArtUploadFile`, image previews use `ArtUploadImage`, structured spreadsheet imports use `ArtExcelImport`, and resource-library selection uses `ArtResourcePicker`. Business views must not implement raw upload lifecycles or repurpose `ArtExcelImport` for ordinary files. Do not place an `ElButton` inside `ElUpload`'s own button-like trigger; shared upload triggers use a non-interactive visual child.
- Business views must use the shared `ArtDialog` and `ArtDrawer` overlay abstractions instead of raw Element Plus overlays.
- Do not leave `console.log` or `console.debug` in business views. Use visible user feedback for demonstrations and controlled diagnostics for actionable failures.
- Never use `transition: all` or `transition-all`; enumerate the properties that actually animate. Preserve the global reduced-motion fallback.
- Give images meaningful `alt` text (or empty `alt` for decoration) and explicit intrinsic dimensions to prevent layout shift.
- Make dark mode follow the application's theme state and shared theme variables, not only the operating system's `prefers-color-scheme` value.
- Run `pnpm ui:audit` after user-facing changes. If the audit reports an existing violation, fix the shared pattern rather than weakening the rule; use an allow marker only for a correctly implemented composite ARIA widget.

## Maintain Type And Async Integrity

- Use `unknown` plus narrowing; do not introduce broad `any`, unsafe casts, or untyped state to silence errors.
- Treat database JSON, browser SDK globals, third-party callbacks, and dynamic API results as untrusted boundaries. Validate or normalize fields before returning a business DTO.
- Never use `as unknown as` in ordinary business code. If a framework or generated-client limitation makes an assertion unavoidable, keep one documented assertion in the smallest adapter boundary and expose a typed API to all callers.
- Do not tighten a non-generic shared component type by forcing every business DTO to add an index signature. Design the generic component boundary first, then migrate callers with a passing typecheck.
- Keep public functions, component exposes, emits, API payloads, and table/form records explicitly typed.
- Preserve error causes when replacing technical errors with user-facing errors.
- Pair loading changes with `finally`; prevent duplicate submissions and stale async results where relevant.
- Do not swallow unexpected failures silently. Return or throw according to the existing boundary contract.

## Refactor Completely

When consolidating code:

1. Move behavior into the canonical module.
2. Update every import and caller.
3. Delete the replaced implementation and its obsolete tests.
4. Merge meaningful test coverage into the canonical module's tests.
5. Search globally for the old symbol, path, raw pattern, and duplicate implementation.
6. Review the diff for accidental encoding, line-ending, generated-file, or unrelated changes.
7. Regenerate repository-owned derived files with their checked-in scripts; never hand-edit generated snapshots.

Do not leave parallel old/new helpers or temporary re-export files unless a documented external compatibility contract requires them.

## Verification Gate

Run focused checks before repository-wide checks:

```powershell
pnpm.cmd exec prettier --write <changed-files>
pnpm.cmd exec eslint <changed-files>
pnpm.cmd exec tsx --test <relevant-tests>
pnpm.cmd exec vue-tsc --noEmit --pretty false
```

Also:

- Run `rg` scans for the anti-pattern being removed.
- Run `pnpm ui:audit` for every user-facing change.
- Run the broader unit suite when a shared utility or API boundary changes.
- Build when module moves or exports could affect bundling.
- For user-facing changes, verify representative success, loading, empty, error, retry, and narrow-width states in a real browser.
- Report pre-existing failures separately from failures introduced by the change.

Completion requires migrated callers, deleted obsolete code, passing relevant checks, and evidence that the targeted anti-pattern no longer remains.
