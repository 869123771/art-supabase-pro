# Shared Component Placement

Shared components are organized by responsibility, not by the page that first needs them. Search the closest existing category before adding a directory, and do not use `layouts` or `others` as catch-all locations.

## `core`: domain-independent UI infrastructure

| Directory | Responsibility | Examples |
| --- | --- | --- |
| `core/base` | Small dependency-light display and interaction primitives | icon buttons, copy text, badges |
| `core/forms` | Inputs, selectors, form composition, and validation-aware controls | `ArtForm`, data selectors, upload controls |
| `core/feedback` | Loading, skeleton, empty, error, permission, and status feedback | `ArtAsyncState`, `ArtEmptyState`, `ArtPermissionGuard` |
| `core/surfaces` | Reusable visual containers and section chrome | `ArtSectionCard`, `ArtSectionTitle` |
| `core/layouts` | Application shell, page geometry, navigation, and structural flow | page shell, page section, menu, header, timeline |
| `core/tables` | Table rendering, querying, pagination, and table tooling | `ArtTable`, `ArtTableQuery` |
| `core/dialogs` | Generic modal containers and dialog infrastructure | `ArtDialog` |
| `core/drawers` | Generic drawer containers and drawer infrastructure | `ArtDrawer` |
| `core/media` | Image, file-preview, audio, and other media presentation | image cropper, preview controls |
| `core/charts` | Domain-independent chart wrappers | chart containers and chart primitives |
| `core/theme` | Theme-aware UI controls and visual tokens exposed as components | theme controls |
| `core/views` | Framework-level reusable view shells, not business feature pages | exception or framework view infrastructure |
| `core/widget` | Small framework widgets that do not fit a business domain | reusable utility widgets |

`core/others` is legacy only. Do not add a new component there. Move a legacy component only when it is already being materially refactored and the move can be verified without broad unrelated churn.

## Cross-repository import paths

Business modules under `modules/**` also build against a pinned, separately distributed `art-supabase-pro` package. A shared component's source path is therefore part of their integration contract. Before relocating one, verify that the pinned platform package contains the new path, update every module import and dependency pin together, and run the standalone module typechecks. `ArtIconButton` currently stays under `core/widget/art-icon-button` for this reason.

## `business`: shared domain-aware components

Use `src/components/business` for components reused across pages that understand business records or call exported `src/api/**` functions. They may compose `core` components but must not access transport clients directly.

Examples:

- `ArtEmployeeSelect`: tenant-scoped employee lookup and employee identity display. `allowAllTenantRead` enables aggregate search only for platform super administrators in the all-tenant scope; write targets still come from the owning form.
- `BusinessWorkspaceHeader`: shared business workspace identity and overview metrics.
- `BusinessMenuFilter`: menu-tree search, selection, counts and complete states; each feature supplies its own visible menus and business statistics.
- Business record links, history, and permission-aware action surfaces.

An employee selector belongs in `business`, not `core/forms`, because it depends on the employee domain and its API contract. A generic paged table selector remains in `core/forms`.

## Page-local components

Keep a component under `src/views/<domain>/<feature>/modules` when it is only meaningful to one feature, depends on that feature's workflow state, or would expose a domain-specific API that no other page consumes.

Promote it only after a real second use or when the platform deliberately establishes a shared contract.

## Placement decision

Before creating a component, decide in this order:

1. Is it page-specific? Keep it in the feature's `modules` directory.
2. Is it shared but domain-aware or API-backed? Put it in `components/business`.
3. Is it domain-independent? Place it in the matching `components/core/<responsibility>` directory.
4. If no category fits, document the missing responsibility before adding a new top-level category. Do not default to `layouts` or `others`.

Each reusable component keeps its `README.md`, public types, usage contract, and complete loading/empty/error behavior beside the implementation.

## Component names

Keep explicit `defineOptions({ name })` names in PascalCase and unique across the host and all business repositories. A route entry owns the route's component name; its reusable implementation uses a distinct responsibility name such as `MdmOutboundRuleWorkspace`. Keep permission codes tied to the business route. `pnpm ui:audit` checks static component names across repositories and rejects duplicates or invalid names. Missing source directories in optional repositories are skipped; failures while reading existing module sources must fail the audit.
