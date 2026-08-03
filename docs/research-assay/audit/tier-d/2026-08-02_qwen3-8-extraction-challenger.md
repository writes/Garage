# Tier D — Qwen 3.8 as extraction-model challenger (TERSE)

- **assay_id:** `2026-08-02_qwen3-8-extraction-challenger`
- **date:** 2026-08-02
- **source:** `https://qwen.ai/blog?id=qwen3.8` (operator link)
- **fetch_status:** **unreachable** — the given URL and `qwen.ai/blog` are JS shells with zero
  extractable content; the `qwenlm.github.io/blog` mirror is stale. Secondary coverage was
  supplied mid-assay by the coordinator (verified web roundup + X API-verified Arena post) and
  is weighed below.
- **surface:** infra (secondary: data / CloudFunctions extraction)
- **mechanism_source:** cost-reduction
- **doctrine_fit:** pass (server-side model qualification is the sanctioned path; the kill is
  economic/evidential, not doctrinal)
- **composite:** 6 → **Tier D** (mechanism 1, evidence 2, additivity 1, capacity 2,
  cost_survival 1, testability 1, implementation_cost −2)

## core_claim (falsifiable)

Adopting Qwen 3.8 as challenger/replacement for the pinned `claude-haiku-4-5-20251001` in
CloudFunctions typed extraction (receipt/PDF parsing, voice quick-add) improves extraction
economics via a cheaper frontier open-weight model served through OpenRouter/DashScope.

## Evidence on record (weighed per the model-utilization playbook hierarchy)

Release facts (multi-source coverage, incl. yottalabs.ai verified-facts roundup): Qwen3.8-Max
Preview announced ~2026-07-19; 2.4T-parameter MoE, multimodal; ~984K context / 128K output;
always-on thinking (low/high/xhigh). Preview access ONLY via Alibaba Token Plan/Qoder/QoderWork
at reported "10% of standard rates". **No standalone API, no published per-token pricing, no
model card, no published benchmark table; open weights promised with no date and no license.**
The "second only to Fable 5" claim is internal-evals-only → inadmissible.

Independent signals: (a) Arena.ai, 2026-08-03 (x.com status 2084108703729615026, X
API-verified): Qwen3.8-Max debuted #4 on Frontend Code Arena at 1,668 Elo — behind Claude
Opus 5 (Max) 1,705 and Kimi K3 (Max) 1,676, on par with Claude Opus 5 (High) 1,669; domain
ranks #2 Consumer Product, #3 Brand & Marketing / Reference-based design / Gaming / Content
Creation Tools, #4 Data & Analytics, #5 Simulations. **Caveat (playbook): arena preference Elo
is the WEAKEST admissible evidence class** (LMArena bias finding; private golden sets outrank
public leaderboards) — it confirms frontier-range coding preference, it is NOT task-completion
evidence, and it changes none of the blocking facts. (b) Independent architecture-task eval:
80/100 vs Kimi K3's 83/100 on a 269-file design analysis, zero failed tool calls — the only
datum touching structured tool use; still not typed extraction.

Net: evidence = 2 (benchmark/case-study class for general frontier capability), with an
explicit zero on extraction task-completion.

## Kill reason

1. **Intake-blocked at stage 1.** With no standalone API, pricing, or license, the 7-stage
   protocol cannot proceed to stage 2 (identity/plumbing probe) even if we wanted it; routing
   user receipt data through a preview coding-plan proxy is a privacy non-starter. This also
   caps testability at 1 — the golden-eval death condition is pre-registerable but not
   executable.
2. **The quality axis is saturated.** The pinned Haiku snapshot scores 100% CORE on the golden
   eval; receipt parse is 98.1% field-level with failures being deterministic omissions. Gate
   floors (core 97.5%, money 97%) are met with margin. A challenger can only tie or lose.
3. **The cost mechanism fails even on paper.** Garage AI volume is quota-capped (AI 5/day,
   credit consumables priced above cost) — Claude spend is a rounding error — and the Qwen-Max
   family reference pricing ($1.25 in / $3.75 out per M) is a wash with Haiku 4.5 ($1/$5). A
   2.4T always-on-thinking MoE flagship is the wrong class for a cheap extraction lane.
4. **Qualification cost is real and non-transferable.** Full 7-stage intake, a new vendor
   secret in protected `CloudFunctions/.env*`, a new data-processor disclosure (user
   receipts/voice text to Alibaba Cloud → privacy label + policy update), strict-tool
   wire-shape re-validation, and per-model few-shot re-tuning (the 77→98% prompt gain was
   Haiku-specific) ≈ sprint-plus, against no measurable payoff. Model-drift already burned prod
   once; the pin exists for a reason.

**The observation-only recommendation stands on kill reasons 2–4 — volume/economics arguments
independent of the evidence axis — so the evidence upgrade (0→2 across amendments) is NOT an
adoption signal.** Machine-wide "Qwen via OpenRouter" roster standing is a **trading-repo**
question; nothing here changes it. (Prior art: `2026-07-28_voder` mentions Qwen3 TTS inside a
rejected voice suite — unrelated surface, not a prior assay of this idea.)

## biggest_risk

The economics leg assumes Garage AI volume stays quota-capped-trivial and GA pricing lands near
the family reference. If Qwen3.8 reaches GA with a standalone API + aggressive pricing, or open
weights land with a permissive license, AND Garage extraction spend becomes material or the
Haiku pin is deprecated/repriced — that changed circumstance is a genuinely new, sharper intake
(e.g. "replace deprecated extraction pin"), not a re-fish of this row. Absent such a trigger:
observation-only; do not re-fish.
