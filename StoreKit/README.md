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
| `lore_plus_monthly` | $5.99 | 1 month (`P1M`) | 7-day free trial (`P1W`, free) |
| `lore_plus_annual` | $34.99 | 1 year (`P1Y`) | 7-day free trial (`P1W`, free) |
| `lore_plus_lifetime` | $99.99 | non-consumable (one-time) | — |

> Source of truth = `StoreKitService.ProductID` + `StoreKit/Lore.storekit`. App Store Connect product IDs/prices MUST match these exactly, or `Product.products(for:)` returns nothing and purchases fail.

Because both products share one subscription group, intro-offer eligibility is
per-group. `StoreKitService.eligibleFreeTrialDescription(productID:)` also
requires a current free-trial offer and derives its duration before the paywall
CTA promises one.

## iOS payment compliance

Lore+ unlocks digital features and content inside the iOS app. Under App Store
Review Guideline 3.1.1, that purchase path uses Apple In-App Purchase through
StoreKit 2. The 2026-07 premium audit found no Stripe SDK, checkout URL, billing
portal, or Stripe API call in the iOS app. Do not add a Stripe purchase button
to this paywall without a separately reviewed storefront/entitlement strategy.

The runtime accepts a verified transaction whose StoreKit `ownershipType` is
Family Shared. The local products currently have `familyShareable: false`,
matching the conservative launch configuration. Enabling Family Sharing is an
App Store Connect business decision and must be mirrored here for testing; do
not flip only one side.

## Wiring it into the scheme

The generated shared `Lore` scheme does not currently reference this file. On a
development machine, after `xcodegen generate`:

1. Xcode → **Product → Scheme → Edit Scheme… → Run → Options**.
2. **StoreKit Configuration** → select `StoreKit/Lore.storekit`.
3. Run in the simulator. `Product.products(for:)` now returns these two products
   with localized `displayPrice`, `product.purchase()` shows the test sheet, and
   `Transaction.currentEntitlements` reflects the test purchase.
4. **Debug → StoreKit → Manage Transactions** to reset/refund and re-test the
   trial-eligibility branch (subscribe once → the CTA should drop the trial copy
   and read "Subscribe").

The internal UUIDs here are placeholders; Xcode fills real ones on first open.
The `productID`s are load-bearing. The paywall displays only StoreKit's
localized `Product.displayPrice`, never the numeric values in this README.

## Relationship to RevenueCat (the P3 server-side truth)

This file drives **StoreKit 2 directly** — the client path adopted now. At P3,
RevenueCat becomes the server-side entitlement truth (its webhook writes the
`entitlements` row `EntitlementStore` reads) and the primary purchase driver
(`Purchases.shared`, which runs on StoreKit 2 under the hood). This
configuration file stays useful for offline/simulator testing of the on-device
belt-and-suspenders read. See the reconciliation TODOs in `StoreKitService.swift`
and `PaywallView.swift`. Do **not** run a second raw purchase path in parallel
with RevenueCat once it exists (docs/16 §1: the double-bookkeeping trap).
