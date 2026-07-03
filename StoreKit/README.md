# StoreKit configuration — `Lore.storekit`

A local **StoreKit Configuration file** so the Lore+ purchase, 7-day trial
eligibility, and restore can be exercised in the simulator with **zero App Store
Connect / RevenueCat dependency** (docs/16-APPLE-TOOLKITS.md §1: "do this during
P1/P2 so the paywall UI is real before the money plumbing is").

## What it defines

One subscription group **Lore+** with the two live products, matching
`StoreKitService.ProductID` and App Store Connect (docs/10 §6, docs/00 §7):

| Product ID | Price | Period | Intro offer |
|---|---|---|---|
| `lore_plus_monthly_4_99` | $4.99 | 1 month (`P1M`) | 7-day free trial (`P1W`, free) |
| `lore_plus_annual_29_99` | $29.99 | 1 year (`P1Y`) | 7-day free trial (`P1W`, free) |

Because both products share one subscription group, intro-offer eligibility is
per-group — exactly what `StoreKitService.isEligibleForIntroOffer(productID:)`
reads and what the paywall CTA branches on.

## Wiring it into the scheme (Xcode-gated — cannot be done from CLT)

There is **no Xcode on the build machine** (Command Line Tools only), so this
step is a to-do for the first machine with Xcode, after `xcodegen generate`:

1. Xcode → **Product → Scheme → Edit Scheme… → Run → Options**.
2. **StoreKit Configuration** → select `StoreKit/Lore.storekit`.
3. Run in the simulator. `Product.products(for:)` now returns these two products
   with localized `displayPrice`, `product.purchase()` shows the test sheet, and
   `Transaction.currentEntitlements` reflects the test purchase.
4. **Debug → StoreKit → Manage Transactions** to reset/refund and re-test the
   trial-eligibility branch (subscribe once → the CTA should drop the trial copy
   and read "Subscribe").

The internal UUIDs here are placeholders; Xcode fills real ones on first open.
The `productID`s and prices are the load-bearing values and are correct as-is.

## Relationship to RevenueCat (the P3 server-side truth)

This file drives **StoreKit 2 directly** — the client path adopted now. At P3,
RevenueCat becomes the server-side entitlement truth (its webhook writes the
`entitlements` row `EntitlementStore` reads) and the primary purchase driver
(`Purchases.shared`, which runs on StoreKit 2 under the hood). This
configuration file stays useful for offline/simulator testing of the on-device
belt-and-suspenders read. See the reconciliation TODOs in `StoreKitService.swift`
and `PaywallView.swift`. Do **not** run a second raw purchase path in parallel
with RevenueCat once it exists (docs/16 §1: the double-bookkeeping trap).
