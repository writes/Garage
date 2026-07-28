# Tier D — VODER (local voice-processing suite)

- **assay_id:** `2026-07-28_voder-voice-processing-suite`
- **date:** 2026-07-28
- **source:** `https://github.com/HAKORADev/VODER` (operator-supplied link, fetched)
- **surface:** ai (secondary: voice quick-add)
- **mechanism_source:** tool-adoption
- **doctrine_fit:** **FAIL**
- **composite:** Tier D — do not adopt; do not re-fish

## core_claim (falsifiable)

Adopting VODER — a Python suite bundling Whisper ASR, Qwen3/Fish-Audio TTS, Seed-VC voice
conversion, ACE-Step music generation, BS-RoFormer separation and speaker diarization — would
improve Garage's voice quick-add accuracy.

## Verdict

**Rejected on three independent grounds, any one of which is sufficient.**

**1. It cannot run where the feature runs.** Garage is a native iOS app, and the native stack is
locked. VODER is Python, wants a GPU (4 GB+ VRAM recommended) and 12 GB RAM minimum. Using it means
standing up a GPU service and shipping the user's recorded audio off-device — a privacy regression
against the app's Trust Pledge and against `SFSpeechRecognizer`, which already runs on-device for
free. That is a re-platform of the voice path, which doctrine forbids.

**2. AGPL-3.0.** Garage is a closed-source commercial app. AGPL's network clause attaches
obligations when the covered work is made available over a network — precisely the deployment shape
adoption would require. This is a licensing hazard, not a licensing inconvenience.

**3. It solves a problem Garage does not have.** Garage's voice bottleneck is short-utterance
dictation of *automotive vocabulary* — "rotors" heard as "routers", "Mobil 1" as "mobile one".
VODER's centre of mass is synthesis, cloning, music and separation. Its ASR is Whisper, which has
no equivalent of `contextualStrings`, so it would not even address the specific failure mode.

Maturity is a secondary concern but reinforces it: single developer, PRs not accepted, 157 stars.

## What was done instead (2026-07-28, same day)

The measured wins on this path needed no dependency at all:

- `contextualStrings` biasing the recogniser toward automotive vocabulary plus the user's own make
  and model — this attacks the exact failure mode above, *before* the transcript exists.
- Awaiting the recogniser's FINAL result instead of returning the last partial, which had been
  dropping the tail of every sentence.
- Device locale instead of a hardcoded `en-US`.
- Forced strict tool use on the extraction call, which removed the malformed-JSON failure class
  outright and constrained `entryType` to an enum.

## death_condition

Revisit only if ALL of: (a) Apple's on-device recogniser is demonstrably the accuracy ceiling on a
measured Garage-specific golden set, (b) a permissively-licensed equivalent exists, and (c) it runs
on-device via Core ML. Absent all three, this ground is dead — do not re-fish.
