# Assay: "Ask Garage" — history-aware AI mechanic chat

- **assay_id:** `2026-08-02_ask-garage-history-aware-ai-chat`
- **date:** 2026-08-02 · **tier:** B · **composite:** 10 · **retention:** SUMMARY
- **source:** operator-paste:2026-08-02-feature-innovation-sweep (operator-idea, paste-only)
- **surface:** ui (secondaries: data — history grounding; payments — credit metering; infra — new CloudFunction)
- **mechanism_source:** real-user-value · **doctrine_fit:** pass

## Core claim

An in-app "Ask Garage" AI mechanic chat improves Pro conversion and engagement via
advisory answers grounded in the vehicle's VIN and full in-app service history,
metered on the existing receipt-credits consumable + Pro quota plumbing.

## Scores

| axis | score | note |
|---|---|---|
| mechanism | 2 | Grounding on owned history is real first-principles RAG value — but only for the maintenance-guidance slice ("what at 60k", "you did brakes 8k mi ago"). The headline hooks (noise-from-text, quote-fairness without regional labor data) outrun the mechanism. |
| evidence | 2 | Case-study level: MyAutoLog ships this as headline Pro, MyGarage+ persona, FIXD advisory upsell at $99.99/yr, RevenueCat 2026 metered-credit convergence. All shipping evidence, zero traction/causal evidence; paste-only, unverified. |
| additivity | 2 | All current Garage AI is single-shot extraction (voice/receipt/oil) — advisory Q&A is new in-app. Discounted because the advice itself is commodity (paste history into free ChatGPT); only the grounding convenience is truly additive. |
| capacity | 2 | Server-side Claude via CloudFunctions scales; long histories need summarization (known pattern); metering caps spend. |
| cost_survival | 2 | Verified plumbing exists (`claudeProxy.ts`, `creditLedger.ts`, `receiptQuota*.ts`, `reconcileReceiptCreditPurchase.ts`, RC webhook). Cents-per-conversation vs credit pricing is favorable; per-message vs per-conversation metering must be decided up front (multi-turn ≠ one receipt scan). |
| testability | 2 | Pre-registrable: golden-set of ~50 real owner questions (repo already runs golden evals for voice), grounded-vs-ungrounded comparison, credit-attach A/B with a numeric death condition. |
| implementation_cost | −2 | NOT "just a new prompt surface": multi-turn streaming UI, conversation state, prompt-injection hardening (user-authored history text enters the prompt), liability/disclaimer UX, moderation, eval harness, consent gating. Quarter-class with a permanent prompt/model-drift tax. |

## Biggest risk

The headline hooks (noise diagnosis, quote-fairness) exceed what the owned data can
ground, so the chat degrades into confident generic advice — simultaneously a
safety/liability exposure and exactly the FIXD-style advisory-upsell reputation
(see `tier-d/2026-07-11_consumer-obd-dongle-integration.md`) that dilutes the
resale-records trust wedge the product is built on. Thesis fit is double-edged:
more chat → more reasons to log → richer history strengthens the dossier, but the
brand promise is "trustworthy records," not "AI opinions."

## Gating constraints (why not Tier A)

1. Composite 10 < 11.
2. The queued App Store 5.1.2(i)/AI-consent UI decision blocks ANY new AI surface
   shipping user data to the Claude API; this feature sends the entire service
   history, the most consent-sensitive payload yet.
3. WTP is unvalidated — three competitors shipping a feature is survivorship-prone
   shipping evidence, not revenue evidence.
4. Scope containment is the make-or-break design decision: launch framed around the
   defensible slice (history-grounded maintenance guidance + "what did I pay last
   time" quote context), not open-ended diagnosis.

## Revisit trigger (Tier B)

The queued 5.1.2(i)/AI-consent UI decision ships AND a cheap pre-registered
golden-set eval (~50 real owner questions) shows history-grounded answers
materially beat an ungrounded baseline on usefulness/safety-of-advice; OR credible
traction/revenue evidence lands for MyAutoLog/MyGarage+-style in-app advisory
chat, firming up WTP beyond mere competitor shipping.
