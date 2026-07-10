# Gemini cross-check of Passes A+B — triage (2026-07-10)

Read-only cross-check (Gemini 3.1 Pro High, 97KB evidence diff). 8 findings; verified in code:

| Finding | Verdict | Action |
|---|---|---|
| Quota deducted before Anthropic call — upstream failure burns user quota | **CONFIRMED** | Pass C2 F1: refund on non-user-fault failure |
| Stale guard `<=` drops same-millisecond events non-deterministically | **CONFIRMED** (line 190) | Pass C2 F2: equal-timestamp tiebreak — revocation wins (fail-safe) |
| `isActive = entitlementIds.includes("pro")` ignores `event.type` — an EXPIRATION event listing "pro" RE-GRANTS Pro | **CONFIRMED — CRITICAL, pre-existing** (survived Pass A unchanged; tests sidestepped it with empty arrays) | Pass C2 F3: type-aware mapping (grant-set types require pro; EXPIRATION always deactivates) + tests both ways |
| Rules allow client self-write of `subscription` | **KNOWN** (P0.0 expected-failure) | Operator-gated rules fix (already queued) |
| CSV sanitizer checks only `value.first` — leading space bypasses (Excel trims) | **CONFIRMED** | Pass C2 F5: first non-whitespace char + control-char aware |
| `attachmentPaths` never passes `safeFreeText` | **CONFIRMED** | Pass C2 F6: sanitize each path |
| Swift 6: stored non-Sendable closures on @MainActor classes (×2 claims) | **REFUTED BY COMPILER** — `SWIFT_STRICT_CONCURRENCY: complete` + `SWIFT_VERSION: 6.0` and the build is green; the compiler enforces what the reviewer pattern-matched | none |

Score: 5 confirmed / 1 known / 2 refuted. The cross-check lane pays for itself.
