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

## Visual behavior

The dialog is one split workspace rather than separate nested cards: the source list or tree is the primary pane, and the optional selected summary is a quieter secondary pane. Keep business-specific labels and icons outside this core component; use `label-key` and `description-key` to provide meaningful context.
