# Cadence

A private conversational-calibration wearable. The phone listens, separates your
voice from theirs, measures how far your pace, volume and airtime have drifted
from the person in front of you, and pulses your watch when you have run ahead.
Nobody else in the room knows it happened.

Standalone. Own repo, own backend, own database. It does not read from or write
to any other app or system.

## How it works

1. **Capture** — `AVAudioEngine` tap at 16 kHz mono, `.mixWithOthers` so music
   and calls keep playing. Background audio entitlement keeps it alive in pocket.
2. **Speaker gate** — near-field heuristic: your phone is on your body, so your
   voice is louder and duller than theirs. Enrolled once, from 60 s of you
   reading aloud. Swappable for a CoreML speaker-verification embedding behind
   the `SpeakerClassifier` protocol.
3. **Features** — per 500 ms frame: RMS dBFS, autocorrelation f0, spectral
   centroid, and syllable rate from the amplitude envelope. All `Accelerate`,
   no speech recognition, no network.
4. **Turns** — frames collapse into turns; anything under 450 ms is a
   backchannel and does not count as taking the floor. Negative latency between
   turns is an interruption.
5. **Divergence** — their last 90 seconds is the target. Six numbers: rate
   ratio, loudness delta, pitch delta, turn-length ratio, talk share,
   interruption rate. Plus a confidence value, because with only one speaker on
   record the comparison is meaningless and should say so.
6. **Cue policy** — a breach must hold for 10 s before it fires, with a 50 s
   global cooldown. Rare cues stay felt.
7. **Review** — session summary, frames and cue log persist locally, then upload
   to Cadence's own Supabase.

## The vocabulary

| Cue | Haptic | Meaning |
|---|---|---|
| `slowDown` | two soft clicks, 280 ms apart | you have accelerated past them |
| `lowerVolume` | one long down-pulse | you are louder than the room needs |
| `yieldFloor` | three quick clicks | you are holding two thirds of the airtime |
| `stopOverlapping` | sharp double retry | you are cutting them off |
| `metronomeTick` | single click | optional: ticks at their turn cadence |

## Verification status

The analysis core (`Sources/CadenceCore`) is Foundation-only on purpose: it
compiles and unit-tests on any machine, not just a Mac. **32 tests, 0 failures,
Swift 6.0.3.** That covers the DSP against synthetic signals with known answers,
turn segmentation, divergence maths, cue timing, sensitivity scaling, and the
speaker gate.

```
swift test          # 32/32 passing
```

The Apple layer (AVFoundation, SwiftUI, WatchKit) is syntax-parsed clean but
**has not been type-checked or run** — that requires Xcode on macOS. Expect to
fix a small number of signatures on the first real build.

Two bugs the tests caught and that are now fixed: the FFT had no window
function, so spectral leakage put the centroid of a 300 Hz tone at 1081 Hz and
would have degraded the speaker gate on device; and the turn threshold was low
enough that a single 500 ms "mm-hm" counted as taking the floor, which inflates
your talk share with the noises you make while listening.

## Setup — there is no Mac in this project

Signing, archiving and TestFlight delivery all run on GitHub `macos-15` runners
against Apple team `XF783932R2`. Certificates are minted headlessly through the
App Store Connect API with openssl — no Mac, no Keychain, no Xcode automatic
signing, which is what caused the August 2026 cert churn on this team.

The repo must be **public**: private repos on this account hit the Actions
spending limit and fail in seconds with no logs.

Provisioning steps and the non-negotiables that came out of previous pipelines:
**[docs/PROVISIONING.md](docs/PROVISIONING.md)**.

Day to day, work happens on Linux:

```
swift build && swift test     # 32/32, no Xcode involved
```

Backend: `psql < backend/supabase/schema.sql`, then deploy `backend/` with
`CADENCE_SUPABASE_URL`, `CADENCE_SUPABASE_SERVICE_KEY` and `CADENCE_API_KEY` set.

## Interface

**iPhone** — onboarding (what it does, mic permission, 60 s voice enrollment,
feel each of the four haptics), then three tabs. *Live* is one ring that opens
and warms as you pull away from them, three balance bars centred on "matched",
and the cue legend visible while running so a buzz never needs decoding.
*History* leads with the only number that proves the thing works — the share of
cues you actually corrected after — then every session, every cue, why it fired,
and whether you closed the gap within thirty seconds. *Settings* is one
sensitivity slider rather than four raw thresholds, haptic previews, and
re-enrollment.

**Watch** — two vertical pages. A glanceable strain ring readable through a
shirt cuff, and the vocabulary for the first fortnight before it becomes habit.

## Build order

- **Phase 0 (this repo)** — capture, DSP, near-field speaker gate, divergence,
  cues, watch haptics, local persistence. Enough to wear tonight.
- **Phase 1** — replace `NearFieldClassifier` with a CoreML speaker-verification
  embedding (ECAPA-TDNN or TitaNet-small), cosine-matched against enrollment.
- **Phase 2** — transcription and language-level coaching (question ratio,
  monologue detection, filler rate).
- **Phase 3** — week-over-week trend on `cadence_weekly`; the only metric that
  matters is `avg_correction_rate` climbing.

## Known edges

- Continuous mic plus on-device DSP runs roughly 8–12 %/hr on the phone. The
  watch is haptics only, deliberately — it is the difference between an evening
  and 90 minutes.
- `WKExtendedRuntimeSession` gives about an hour and is restarted on expiry.
  An `HKWorkoutSession` would run indefinitely but shows as a workout.
- The near-field gate degrades in a loud room and with a phone flat on a table
  between two people. Phase 1 is the fix, not a threshold tweak.
- Recording consent is one-party in Utah and two-party in about a dozen states.
