# Interface Design System

## Direction

Build calm, information-dense enterprise workspaces with clear hierarchy, compact controls, restrained color, and consistent operational feedback. Prefer the established shared shells and tokens over page-local visual inventions.

## Design-reference memory

- Platform-super-marked routes in `public.ai_ui_design_reference` are the living evidence for the owner's preferred UI direction.
- Before designing or materially restyling a page, load the active references and consider `preference_tags`, `note`, `surface_kind`, and `style_snapshot` together. Explicit instructions in the current task always take precedence.
- Treat references as design evidence, not as page templates. Reuse hierarchy, density, spacing rhythm, table treatment, status expression, and interaction patterns only when they fit the new page's job.
- Never copy screenshots, customer records, identifiers, or business values into the design memory. The stored snapshot must remain structural metadata only.
- If a referenced route or source revision has changed, inspect the current route before relying on the saved preference.
- If the database context is unavailable, use this document and the repository's shared components as the fallback, and state that live preference references were not available.

## Established patterns

- Use `BusinessWorkspaceHeader` for operational list/workspace pages and `ArtPageHeader` for standalone detail or configuration pages.
- Keep page identity on the left and compact operational actions on the right.
- In workspace headers, place the platform-super-only design-reference action immediately after the refresh control.
- Prefer compact tables, short search rows, semantic status tags, and one clear primary action per region.
- Use theme tokens, existing spacing tokens, and shared interaction components. Preserve dark mode, responsive behavior, focus visibility, loading, empty, error, and disabled states.

## Access boundary

- The design-reference control and persisted records are for the platform super administrator only.
- Ordinary users must not see the control or read/write the reference records.
