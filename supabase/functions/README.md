# Do not deploy Edge Functions from lore-ios

This directory is **quarantined**. The native app is not a second deploy source.

Canonical implementations live in the `lore` backend repository:

- `delete-account` (fenced, receipt-hashed, tested)
- `landmark-id`
- `sync-apple-purchase`
- `streetview`

A weaker `delete-account` used to live here. Shipping it would bypass the
production deletion fence. CI fails if deployable function source (`index.ts`)
reappears under this path.
