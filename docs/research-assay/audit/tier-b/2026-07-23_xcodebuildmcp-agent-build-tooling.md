# Tier B — XcodeBuildMCP (agent-driven Xcode build/test/simulator MCP server)

- **assay_id:** `2026-07-23_xcodebuildmcp-agent-build-tooling`
- **date:** 2026-07-23
- **source:** `https://x.com/DanKornas/status/2079776174012596241` (tweet announcement) → underlying tool `https://github.com/cameroncooke/XcodeBuildMCP`
- **source_type:** sdk · **fetch_status:** fetched (syndication endpoint + GitHub repo/README cross-verified; oEmbed and direct x.com fetch both blocked/402)
- **surface:** infra (dev tooling / agent-build loop; secondary: performance — agent turn/token efficiency)
- **mechanism_source:** dx-velocity
- **doctrine_fit:** pass (usage-constrained — see biggest_risk)
- **composite:** 9 → **Tier B** · retention **SUMMARY**

## core_claim (falsifiable)

Adopting **XcodeBuildMCP** — a Model Context Protocol server + CLI wrapping `xcodebuild`,
simulator, and device tooling — **improves this repo's machine-brain agent build/test/simulate
loops via structured, typed MCP tool calls in place of raw-shell `xcodebuild` invocation and
manual log parsing.**

## What was fetched

Tweet (@DanKornas, 2026-07-22, recovered via `cdn.syndication.twimg.com/tweet-result?id=...`
after direct x.com WebFetch and `publish.x.com/oembed` both returned HTTP 402):

> "Agents can edit iOS code, but they still need a structured way to drive Xcode. XcodeBuildMCP
> is an MCP server and CLI for agents working on iOS and macOS projects. It helps you run Xcode
> tasks from agent workflows by exposing project, simulator, and app utilities through MCP"

Underlying project confirmed live via GitHub repo + README fetch:
`cameroncooke/XcodeBuildMCP`, MIT license, ~6.1k stars, TypeScript-primary with Swift
components, macOS 14.5+ / Xcode 16.x / Node 18+, MCP server or direct CLI mode, tools for
building/testing for simulator+device, device/simulator management, and project inspection.
Documented drop-in config for Cursor and Claude Code. Uses Sentry telemetry (opt-out available)
— note only, not load-bearing since this is dev tooling, never shipped in the Garage app binary.

## Scores

| axis | score | why |
|---|---|---|
| mechanism | 2 | Real, named mechanism: MCP tool calls return structured/typed responses (simulator lists, build results, app paths) instead of forcing an agent to parse raw `xcodebuild` stdout — plausibly fewer wasted turns/misreads in agent build-verify loops. Not 3: our agents already accomplish every one of these operations today via the Bash tool + `scripts/ci/*`; this is an efficiency/reliability upgrade to an already-working path, not new reachable capability. |
| evidence | 2 | ~6.1k GitHub stars, MIT license, actively released (v2.7.0 as of fetch), maintained by a credible org (Sentry), documented Cursor/Claude Code integrations — real adoption at scale. Not 3: no evidence specific to THIS repo's shape (XcodeGen-generated multi-scheme project, Swift 6 strict-concurrency warnings-as-errors build) — general popularity, not a benchmark against our setup. |
| additivity | 1 | Everything it exposes is already reachable via Bash + `xcodebuild` + `scripts/ci/verify-ios.sh`; matches the same "re-covers ground we already hold" pattern scored for 10x (`2026-06-29_10x-agentic-ios-app-builder`, additivity 1). The gain is convenience/token-efficiency, not new capability. |
| capacity | 1 | Dev tool, orthogonal to runtime/user/vehicle scale (per-invocation local tool, not a product surface) — neutral, same reasoning as the 10x precedent. |
| cost_survival | 2 | MIT license (no commercial-use blocker, unlike 10x's PolyForm Noncommercial), free, runs locally against the developer/agent's own Xcode install — no Firebase/App-Store/subscription/Claude-API cost interaction at all. |
| testability | 2 | Trivially pre-registerable: pilot in ONE agent workflow (e.g., a `dual_agent_loop.py` build-verify step or a single `.claude/` MCP config), run N fixed tasks ("build for simulator + run GarageUnitTests") via MCP vs. today's raw-shell path, measure turn count / token count / error rate, with an explicit death condition (no measurable improvement, or any incompatibility with XcodeGen/Swift 6 strict-concurrency build settings → drop). |
| implementation_cost | −1 | Install (Homebrew or npm) + wire MCP config into agent CLIs + validate against this repo's actual XcodeGen/scheme/Swift-6 setup + write an explicit guardrail so it can never be treated as the CI gate. Real but bounded — roughly a day or two, not a sprint. |

Composite = 2 + 2 + 1 + 1 + 2 + 2 − 1 = **9**.

## Tier rationale

Not D (composite 9 > 6, not refuted, not fully redundant, doctrine_fit ≠ fail — this is pure dev
infra, touches none of the native-iOS/Swift-6/Firebase/secrets/App-Store hard gates). Not A
(composite 9 < 11, even though mechanism ≥ 2 and testability ≥ 1 are both satisfied). Not C — this
isn't primarily a durable-tradeoff teaching moment, it's a concrete, cheap, pilotable tool with a
clear go/no-go. → **Tier B, SUMMARY.**

## biggest_risk

If ever wired in, XcodeBuildMCP-driven "build succeeded" must never be treated by an agent as
equivalent to passing `scripts/ci/{policy-checks,security-checks,verify-ios}.sh` — Law 3 is
explicit that the shell-script CI gate is the sole, deterministic promoter. Secondary risk:
compatibility with this repo's specific setup (XcodeGen-generated `project.yml`, multi-scheme
targets, `SWIFT_STRICT_CONCURRENCY: complete` warnings-as-errors) is unverified — all public
evidence is generic-Xcode-project adoption, not confirmed against our exact configuration.

## revisit_trigger

A machine-brain agent session logs measurable friction or token burn from parsing raw
`xcodebuild` output inside an agent build-verify loop (e.g., inside `dual_agent_loop.py` or a
`.claude/workflows/*` script), **OR** someone runs the cheap pilot described under `testability`
and it shows a real turn/token/error-rate win with zero interference with the CI gate or
XcodeGen/Swift-6 build settings — then integrate as an opt-in agent-side convenience only, never
as a CI-gate replacement.
