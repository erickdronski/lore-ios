# Scanner tech evaluation (owner-supplied repos, 2026-07-10)

Verdict-first review of the nine links, against Lore's constraint set:
native SwiftUI iOS app, pose+geometry+atlas recognition, honesty ladder,
no new paid services, CI-only builds.

| Source | What it is | Verdict |
|---|---|---|
| AR.js + AR.js-Docs | Browser WebAR (marker/location-based, three.js) | REJECT for lore-ios (JS cannot run in native Swift). Its *location-based AR* model is what our scanner already does natively with better sensors. Possible future fit: lore-web /scan camera overlay; not adopted now. |
| mind-ar-js | Browser image tracking | REJECT for native (JS). Image-target tracking natively = ARKit `ARImageAnchor`, no dependency needed. Candidate for a future "plaque image" rung; QR rung below covers the same ground cheaper. |
| HoloLab ARFoundationQRTracking (Unity) | QR pose tracking in Unity AR Foundation | Concept ADOPTED, code rejected (Unity/C#). The idea, QR as a spatial ground-truth anchor, is the valuable core. |
| qrcodereaderview (Android, archived) | Android QR reader view | REJECT (Android, archived). Same concept as above. |
| ar-vos.com | Commercial AR platform | REJECT: paid platform, no-new-costs rule; capability overlaps what we build in-house. |
| Dynamsoft ARCore+QR article | Tutorial: AR + barcode detection | Concept ADOPTED: confirms the marker-assisted AR pattern; their SDK is commercial, ours uses Apple AVFoundation for free. |
| AR-ObjectScanner | ARKit object scanning sample | Interesting for statue recognition via `ARReferenceObject`, but each statue must be 3D-scanned on site: a content pipeline we don't have. Parked as a niche P2 rung. |
| INRIA hal-03250500 | Research paper | NOT RETRIEVABLE (access-denied wall). Revisit if the owner supplies the PDF. |

## What we pulled: the QR MARKER RUNG (rung 0), shipped

The one idea every QR repo shares, done the native way with zero
dependencies: `AVCaptureMetadataOutput(.qr)` on the scanner's existing
capture session. A Lore marker placed at a known spot (museum stand,
partner plaque, city program sticker) encodes
`https://getlore.app/p/<slug>` (or `lore://p/<slug>` / `lore:<slug>`);
scanning it is centimeter-grade ground truth, so the app resolves that
place instantly with the lock haptic and opens its dossier.

Why this elevates the scanner where it is weakest:
- Indoors and in urban canyons, where GPS+compass can never earn Tier A.
- Museums/partners get a zero-setup Lore integration (print a QR).
- Foreign QR codes are deliberately ignored (this is not a QR reader);
  only Lore payloads act, debounced at 5 s per code, all on-device.

Follow-ups: marker analytics (which markers get scanned), a printable
marker generator on lore-web, and, at P1, ARKit image anchors for
markerless plaque recognition.
