# Tier D — minimax-h3-mlx (local 33B video+audio diffusion)

- **assay_id:** `2026-08-04_minimax-h3-mlx-video-audio-diffusion`
- **date:** 2026-08-04
- **source:** `https://github.com/mrbizarro/minimax-h3-mlx` (operator-supplied via
  X post https://x.com/ivanfioravanti/status/2084633339282026622; repo fetched)
- **surface:** infra (secondary: performance, theory)
- **mechanism_source:** none
- **doctrine_fit:** **FAIL**
- **composite:** −1 · Tier D — do not adopt; do not re-fish

## core_claim (falsifiable)

Adopting minimax-h3-mlx (a from-scratch MLX Apple Silicon port of MiniMax-H3, a 33B joint
video+audio diffusion transformer) improves Garage's AI feature surface via locally hosted
generation of synchronized video and audio.

## Verdict

**Rejected on four independent grounds, any one of which is sufficient.**

**1. It cannot run where Garage runs.** Garage is a native iOS app on iPhones. The port targets
macOS Apple Silicon (M3 Ultra-tested) at **~102 GB resident memory** before quantization — two
orders of magnitude beyond any iPhone. The only deployment shape adoption could take is a
parallel Mac-metal generation backend outside Firebase, which doctrine forbids without
overwhelming justification. There is none: nothing in the product needs this.

**2. Generation economics are non-viable at any scale.** ~8.8 minutes per denoising step for a
5-second clip on an M3 Ultra; ~1.2 hours at 8 steps, **~7.3 hours at the typical 50 steps**.
A dedicated ~$10K machine serving roughly three clips a day cannot survive subscription
economics (capacity 0, cost_survival 0).

**3. It solves no Garage problem.** Garage is service logs, resale-ready exports, and
server-side Claude extraction (receipts, voice). No feature in the product or the profit-first
blueprint consumes generative video+audio. mechanism_source = none — this is capability-driven
novelty, not user value (mechanism 0, additivity 0).

**4. Weights license.** The port's code is Apache-2.0, but the MiniMax-H3 **weights** ship
under the non-open "MiniMax H3 Community License": redistribution constraints, commercial-use
restrictions above $20M revenue, territory exclusions. Apache on the code does not cure the
weights for a closed-source commercial app.

Maturity reinforces: 8 stars, 1 fork, 20 commits — early-stage single-dev port.

## Credit where due (the one reference-worthy nugget)

The engineering is honest and validated: numeric parity vs the diffusers reference (DiT error
4.8e-07), and the **AdaLN precompute** trick — precomputing timestep-conditioned weights so a
745 MB cache replaces 26 GB of weights, dropping the resident transformer from 33B to ~20B —
is a genuinely clever inference-memory optimization (evidence 1 for the artifact itself; zero
evidence for any Garage payoff). It has no application in Garage's stack (we run no on-device
diffusion), so it earns a note here, not a Tier-C promotion.

## Precedent

Stage-0 search surfaced the adjacent **VODER** kill
(`tier-d/2026-07-28_voder-voice-processing-suite.md`): local ML suite, killed on
can't-run-where-features-run + license + solves-no-Garage-problem. This assay is a distinct
artifact (generation, not voice processing) but dies on the same three walls plus economics —
the "local heavyweight ML on Apple hardware" ground is now twice-confirmed dead for Garage.

## death_condition

Feasibility is already falsified by the repo's own published numbers (102 GB resident,
7.3 h/clip vs an iPhone app). Reopen ONLY if ALL of: (a) a Garage feature exists whose
validated user value requires generative video/audio, (b) a model of that class runs on-device
on shipping iPhones or inside our existing Firebase backend at viable unit cost, and (c) the
weights carry a license compatible with closed-source commercial distribution. Absent all
three, this ground is dead — do not re-fish.
