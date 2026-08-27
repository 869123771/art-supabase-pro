# Platform tenant scope switcher

Header-level tenant read scope for platform super administrators.

- Hidden for ordinary tenant users.
- `null` means all active business tenants and is intended for read-only overview.
- A concrete tenant ID establishes an explicit mutation context for tenant-owned records.
- Tenant options come from the exported system-management API; the component never accesses the transport client directly.
- The selected scope is stored for the current browser session and reset when the signed-in user changes.
