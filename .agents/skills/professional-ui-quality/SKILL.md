---
name: professional-ui-quality
description: Enforce professional visual design and UI quality gates for art-supabase-pro. Use whenever creating, modifying, refactoring, reviewing, or visually auditing any user-facing Vue page, component, dashboard, table, form, dialog, drawer, empty state, loading state, AI feature, or responsive layout under src. Apply even when the user asks only for functionality and does not explicitly request beautification.
---

# Professional UI Quality

Treat visual quality as part of feature completion. Never hand off a user-facing change that is merely functional.

## Design Direction

Use a modern enterprise logistics style: calm, precise, trustworthy, information-dense without feeling crowded.

- Use the project theme and existing Art/Element Plus primitives as the visual source of truth.
- Prefer neutral surfaces, blue/indigo primary accents, and semantic success/warning/danger colors.
- Use gradients only for restrained emphasis, never as a default card background.
- Build hierarchy with typography, spacing, grouping, borders, and tonal contrast before adding decoration.
- Keep one clear primary action per region. De-emphasize secondary and destructive actions appropriately.
- Use icons to improve scanning, not to decorate every label.
- Preserve consistent radii, card treatment, shadows, control heights, and density across neighboring pages.

## Theme And Box-Mode Coupling

Interactive surfaces must follow both the active theme color and the configured box style. Do not implement a theme-colored hover state without also respecting the root `data-box-mode` value.

- Derive hover, active, and focus colors from `--theme-color`; never hardcode a product accent color.
- In `border-mode`, use a theme-tinted background plus a visible theme-colored border or inset ring. Do not add elevation shadows.
- In `shadow-mode`, use a theme-tinted background plus a soft theme-colored outer shadow. Keep the border transparent and do not add an inset border ring.
- Prefer shared CSS tokens for these mode-dependent treatments so headers, `ArtDialog`, `ArtDrawer`, table tools, and other icon actions remain consistent.
- Preserve keyboard focus visibility in both modes. The focus treatment may be stronger than hover, but it must retain the selected box-mode language.
- When changing a shared interactive pattern, verify both `border-mode` and `shadow-mode` in a real browser before handoff.

## Required Workflow

### 1. Inspect Before Designing

Read the target page, its child modules, one polished neighboring page, and the relevant core component APIs. Identify the page's primary task, information hierarchy, high-frequency actions, and likely viewport constraints.

### 2. Establish Layout Hierarchy

Organize the interface into intentional layers:

1. Page or workflow identity: title, context, status, and primary action.
2. Decision summary: important metrics, warnings, or progress.
3. Main work area: forms, tables, charts, or business content.
4. Supporting details: evidence, metadata, explanations, and audit information.

Avoid undifferentiated stacks of white boxes. Group related content, align edges, and use a consistent spacing rhythm. Prefer 4/8/12/16/24/32px spacing decisions unless an existing component controls spacing.

### 3. Complete Every UI State

Design and implement all states relevant to the workflow:

- loading and refresh;
- empty and first-use;
- error and retry;
- disabled and permission-limited;
- selected, active, warning, and destructive;
- long text, large numbers, missing values, and dense data;
- narrow desktop and mobile-width behavior where applicable.

Do not use raw placeholder text, unstyled fallback blocks, or blank regions when a purposeful state is possible.

### 4. Apply Interaction Quality

- Keep labels concise and make helper text explain consequences or next actions.
- Make clickable regions and button hierarchy visually obvious.
- On table pages with a persistent identity, governance, overview, or explanatory header above `ArtTableQuery`, enable the shared focus mode. Verify that entering focus mode hides non-table context, preserves the query/table/pagination workflow, supports Escape to exit, and restores the prior layout and search-panel state.
- Size fixed operation columns from the rendered controls, cell padding, and intentional gaps. When several compact actions are valid, preserve them and remove compounded child margins instead of compressing the controls or hiding useful actions solely for aesthetics.
- Preserve keyboard focus visibility and sufficient color contrast.
- Do not communicate status by color alone; pair color with text or iconography.
- Prevent accidental horizontal scrolling. Use `min-width: 0`, wrapping, truncation, or responsive grids deliberately.
- Use bounded `ElScrollbar` regions for long drawer, dialog, panel, or page content.

### 5. Reuse The Project System

Apply `art-supabase-pro-conventions` together with this skill. Prefer `ArtTableQuery`, `ArtDialog`, `ArtDrawer`, `ArtForm`, `ArtSectionTitle`, `art-card-xs`, theme variables, and existing global radius tokens. Do not create a competing local design system inside one business page.

When a broadly useful visual pattern is missing, extend the closest shared core component or token before copying page-local implementations across features.

## Mandatory Visual Quality Gate

For every user-facing frontend change:

1. Format, lint, and type-check the changed files.
2. Open the affected workflow in a real browser when practical.
3. Inspect at least the initial view and any scrollable lower content.
4. Check alignment, clipping, horizontal overflow, loading/empty behavior, and console errors.
5. Capture or inspect screenshots at the actual rendered size and iterate on visible defects.
6. Report visual verification and any environment limitation in the handoff.

Do not declare the UI complete based only on source-code review. If browser verification is impossible, explicitly state that the visual gate remains unverified.

## Acceptance Checklist

Before handoff, confirm:

- the primary task and action are immediately understandable;
- typography has clear title, section, body, and metadata levels;
- cards and sections align to a coherent grid;
- spacing is consistent and neither cramped nor wasteful;
- semantic colors are correct and restrained;
- tables, forms, dialogs, and drawers match the surrounding product;
- long content and narrow widths do not introduce unintended horizontal scrolling;
- loading, empty, error, and disabled states look intentional;
- the interface contains no debug labels, awkward copy, or unexplained technical values;
- the browser console has no new errors.

## Design Tool Policy

Use Figma when a supplied Figma file is the design source of truth, when stakeholders need collaborative design approval before implementation, or when exact design-token handoff is required. Do not require Figma for routine feature beautification; this skill and the live product design system remain sufficient for code-first UI work.
