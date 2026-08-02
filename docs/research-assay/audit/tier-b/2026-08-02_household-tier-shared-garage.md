# Assay: Household tier — per-household pricing with a shared garage

- **assay_id:** `2026-08-02_household-tier-shared-garage`
- **date:** 2026-08-02
- **source:** operator-paste: 2026-08-02 feature-innovation research sweep (operator-directed)
- **tier:** B · **retention:** SUMMARY · **doctrine_fit:** pass

## Core claim

A per-household subscription tier with a shared multi-member garage improves
ARPU and retention via family-circle pricing (Life360 model) capturing
multi-driver households that per-uid Pro cannot serve.

## Scores

| axis | score | note |
|---|---|---|
| mechanism | 2 | Real first-principles case (teen driver logs fuel, spouse gets reminders, aging parent's car managed remotely; circle pricing captures WTP above single-user Pro). Docked one point: the Life360 analogy is imperfect — location safety is *intrinsically* multi-member, while maintenance logging is usually one household record-keeper, whom Pro (5 vehicles, server-enforced) already serves. |
| evidence | 1 | Life360 ($69.99–$199.99/yr per circle, ~2.2M circles, ~$385M ARR) is shipped-at-scale proof of circle pricing — in an adjacent category. Direct evidence for THIS claim is thin: the CARFAX review asks for more vehicle *slots*, not shared access; AUTOsist multi-user is B2B fleet. Zero Garage-native requests recorded. |
| additivity | 2 | Genuinely new: multi-sign-in on one garage, per-member attribution, pooled cross-Apple-ID billing. But the largest slice of the claimed value ("manage the family's cars") is already reachable via Pro's 5-vehicle cap under one admin. |
| capacity | 2 | Households are small-N; Firestore shared collections scale fine. Pooled `getAfter` counters move to a household doc — harder, not breaking. |
| cost_survival | 1 | Raises ARPU per circle but cannibalizes multi-Pro households; Apple Family Sharing (StoreKit + RevenueCat both support it) shares one purchase across up to 6 Apple IDs, constraining "per-household" enforcement and pricing headroom. Plausible-favorable, not clean. |
| testability | 2 | Cheaply falsifiable *before* build: fake-door teaser/waitlist to Pro users via the existing experimentation stack (PR #23), with a pre-registered conversion death condition. |
| implementation_cost | −3 | Firestore rules are strictly per-uid single-owner across every collection (`request.auth.uid == resource.data.userId`; vehicle cap via same-batch `getAfter` counter on `users/{uid}.vehicleCount`). Household layer = membership docs + invite flows + full rewrite of a PROTECTED surface (`firebase.firestore.rules`) with real attack surface, pooled-limit semantics, shared-record account-deletion semantics (Apple deletion requirement: what happens to records a departed member authored?), RevenueCat family-entitlement plumbing, and a **permanent ACL tax on every future collection**. |

**Composite: 7** → Tier B (7–10 band).

## Revisit trigger (the one event that reopens this)

Garage-native demand for **shared access** (not slots): a pre-registered
fake-door test ("Family garage" teaser/waitlist shown to active Pro users)
converts ≥5% within 30 days, **OR** ≥10 organic support/review requests
specifically for multi-member access, **OR** vehicle-limit telemetry shows Pro
accounts hitting the 5-cap with evidence of distinct drivers.

Cheaper intermediate worth testing first: an **additional-vehicle-slots upsell**
(pricing/counter change only, no rules rewrite) — it serves the actually-
documented pain and, if it underperforms with multi-driver households, that
itself is evidence for or against the shared layer.

## Biggest risk

The demonstrated demand is for more vehicle SLOTS under one admin — largely
served today by Pro's 5-cap or a cheap slot upsell — not for multi-user shared
access. Building the household data layer would spend a quarter-plus of
protected-surface security rewrite on a feature whose real revenue a pricing
change could have captured.
