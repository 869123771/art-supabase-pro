# ArtDataSelect

`ArtDataSelect` provides shared table and tree selectors for single- and multi-select workflows.

## Variants

- `table-single.vue`: paged or local table single select.
- `table-multiple.vue`: paged or local table multiple select with a selected summary panel.
- `tree-single.vue`: hierarchical single select.
- `tree-multiple.vue`: hierarchical multiple select with independent parent/leaf selection by default.

All variants delegate to `index.vue` and share the contracts exported by `types.ts`.

## Data contract

- Use `row-key` for the stable record identifier and `label-key` for the primary display text.
- Use `description-key` for compact secondary context such as a code or owner.
- For tree data, use `children-key` and `disabled-key`; disabled nodes remain readable as grouping context but cannot be selected.
- When a selected value may not exist in the current page of results, provide `selected-data` so its label and description remain available.
- Remote loaders use `api-fn` and should return a list plus an optional total. Loading, empty, selected, and pagination states are owned by the component.

## Request lifecycle and recovery

Only the latest load may update rows, totals, loading state, or table/tree selection synchronization. Closing/unmounting invalidates unfinished work; replacing `api-fn` while open resets the page and loads the new source. This is result invalidation, not transport cancellation.

A thrown/rejected loader error or a returned `error` is shown through the shared inline retry state, never as an empty successful result. Search and selected rows stay available, and retry reuses the current query. Confirmation is disabled while loading or after failure; cancel stays available. `load-error` exposes the current raw diagnostic cause through all four variants; do not display that raw value or add another generic error toast. Providers retain responsibility for access control and any existing business-specific notifications.

## Visual behavior

The dialog is one split workspace rather than separate nested cards: the source list or tree is the primary pane, and the optional selected summary is a quieter secondary pane. Keep business-specific labels and icons outside this core component; use `label-key` and `description-key` to provide meaningful context.

The search/list/selected workspace shares a viewport-bounded height. Only list/tree and selected entries scroll; pagination is outside the shrinking list body. Narrow screens stack the selected summary with a bounded share of the available height and allow pagination controls to wrap. Do not restore fixed per-pane heights: they hide pagination behind the dialog footer at low viewport heights.
