---
name: professional-ui-quality
description: Design, improve, review, and visually verify professional user-facing UI for art-supabase-pro. Use for any Vue page, component, dashboard, table, form, dialog, drawer, navigation, empty/loading/error state, responsive layout, theme treatment, accessibility review, UI audit, screenshot comparison, or visual polish under src. Apply to routine frontend changes even when the user asks only for functionality, and use the formal review mode when the user asks to assess UI quality without implementation.
---

# Professional UI Quality v2

Treat visual quality, usability, accessibility, and rendered verification as feature requirements. Produce UI that belongs to this product instead of a generic template.

## Select The Operating Mode

Choose one mode before acting:

- **Create**: new page, new workflow, or substantial redesign. Read [project-visual-baseline.md](references/project-visual-baseline.md), [creative-direction.md](references/creative-direction.md), and [web-interface-checklist.md](references/web-interface-checklist.md).
- **Improve**: targeted polish or feature work inside an established page. Read [project-visual-baseline.md](references/project-visual-baseline.md) and the relevant sections of [web-interface-checklist.md](references/web-interface-checklist.md). Preserve the established page language unless the user requests a redesign.
- **Review**: visual, UX, accessibility, PR, or design-system audit. Read [project-visual-baseline.md](references/project-visual-baseline.md), [web-interface-checklist.md](references/web-interface-checklist.md), and [review-rubric.md](references/review-rubric.md). Report findings; do not implement fixes unless requested.

Use [review-rubric.md](references/review-rubric.md) for every formal score, approval decision, or final quality report. Do not load creative guidance for a narrow maintenance change with a fixed visual direction.

## Establish The UI Contract

Before implementation or review, identify:

1. The user's primary job and the one action that should dominate the region.
2. The information hierarchy: identity, decision summary, main work area, and supporting evidence.
3. The required states: success, loading, empty, error/retry, disabled/permission-limited, selected, long content, and dense data.
4. The viewport, theme, box-mode, localization, and permission constraints that can change the result.
5. The source-of-truth order: explicit user reference or Figma, existing project system, polished neighboring workflow, then this skill's defaults.

Inspect the target, child modules, relevant Art/Element Plus APIs, and at least one polished neighboring workflow before making visual decisions.

## Build With Project Identity

- Apply `art-supabase-pro-conventions` together with this skill.
- Reuse Art components, Element Plus primitives, theme tokens, global radii, and existing layout patterns. Extend a shared pattern before copying it into several pages.
- Keep the product calm, precise, trustworthy, and operationally dense. Make one visual idea carry the region; keep surrounding treatment disciplined.
- Use typography, spacing, grouping, tonal contrast, and alignment before decoration.
- Derive interactive colors from `--theme-color`. Never hardcode a product accent or create a competing local design system.
- Prefer `ArtTableQuery`, `ArtDialog`, `ArtDrawer`, `ArtForm`, `ArtSectionCard`, `ArtSectionTitle`, and bounded `ElScrollbar` regions where their established responsibility applies. Use `ArtSectionCard` for titled content surfaces with loading, empty, or error states; reserve raw `art-card-xs` for untitled compact surfaces and sticky action regions.

## Enforce Perceptible Hierarchy

- A background, filled, tonal, selected, or elevated variant must be visibly distinct at actual rendered size. A technically different but imperceptible color is a defect.
- Preserve readable neutral, hover/focus, and current/selected levels. Do not rely on color alone for business status.
- For deliberately borderless tonal navigation, create separation with fill contrast; reserve a ring for keyboard focus instead of adding a decorative border.
- In `border-mode`, elevated controls use the project's border/inset-ring language without elevation shadows.
- In `shadow-mode`, elevated controls use a restrained theme-colored outer shadow with a transparent border.
- Validate light/dark themes and both box modes whenever a shared interactive surface changes.

## Complete Interaction And Content

- Use semantic interactive elements, visible `:focus-visible` treatment, accessible names, and forgiving hit areas.
- Keep labels action-specific. Helper, empty, and error copy must explain consequences or the next useful action.
- Employee/person controls must show recognizable identity through `ArtEmployeeSelect` (`员工姓名 · 工号`, with organization/position context in the picker); exposing a UUID as option or selected text is a UI defect.
- Do not block paste or browser zoom. Respect reduced motion and avoid decorative animation that delays work.
- Prevent accidental horizontal scrolling. Use `min-width: 0`, wrapping, truncation with a full-value path, and responsive grids intentionally.
- For table workspaces, preserve query, table, operation, pagination, loading, empty, and focus-mode behavior as one workflow.
- Do not hand-compose a titled card from `art-card-xs`, `ArtSectionTitle`, `ElSkeleton`, and `ArtEmptyState`. Route whole-card state through `ArtSectionCard` so header spacing, state priority, retry behavior, and responsive actions remain consistent. Retain an inner `ArtAsyncState` only when it controls a distinct sub-region and adjacent filters, actions, or metrics must stay visible.
- Size fixed operation columns from rendered controls and intentional gaps; do not hide valid actions merely to make the column narrower.

## Verify The Rendered Result

Run focused formatting, ESLint, type checking, and the repository UI audit. When CSS or SCSS changes, run focused Stylelint as a separate gate; ESLint and `ui:audit` do not replace it. Then verify the affected workflow in a real browser.

Use the bundled browser audit when a locally reachable URL is available:

```powershell
pnpm.cmd exec node .agents/skills/professional-ui-quality/scripts/visual-audit.mjs --url "http://127.0.0.1:3006/#/route" --selector ".target-root" --viewports "1440x900,1280x800"
```

Add `--themes "light,dark"`, `--box-modes "border-mode,shadow-mode"`, and `--storage-state "playwright/.auth/user.json"` when those variants are relevant. Read the generated JSON report and inspect every screenshot at 100% scale. The script is evidence collection, not a substitute for visual judgment.

Use test or sanitized data for screenshots. Keep generated evidence under the ignored `.artifacts` directory; do not commit or share screenshots that contain tenant, customer, credential, financial, or personal data.

Check at minimum:

- initial and lower scrollable content;
- alignment, clipping, wrapping, horizontal overflow, and sticky regions;
- relevant loading, empty, error, disabled, selected, and long-content states;
- keyboard focus, interaction feedback, console errors, and narrow desktop behavior;
- light/dark and box-mode variants affected by shared styling.

Do not declare completion from source review alone. If browser verification is impossible, state that the visual gate remains provisional.

## Report The Outcome

For implementation, lead with the visible result, then list verification evidence and limitations. For reviews, use the severity, scoring, evidence, and verdict format in [review-rubric.md](references/review-rubric.md). Keep findings concrete and tied to a rendered or source artifact.

## Design Tool Policy

Use Figma when it is the supplied source of truth, collaborative approval is required, or exact token handoff is needed. Do not require Figma for routine code-first improvement; the live product and project design system remain authoritative.
