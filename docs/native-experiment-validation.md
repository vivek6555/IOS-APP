# Physical iPhone validation protocol

This is an **execution protocol, not a results report**. Run only after the native harness builds. Sources: feasibility blueprint sections 9, 11 and 12 and `native/CaptureExperiment/README.md`.

## Controls and evidence

Use the iPhone 16 and iPhone 15 Pro reported by the operator. Neither is automatically the product's minimum supported device. Record exact OS/build, Xcode/build, source revision (`git rev-parse HEAD` plus whether modified), app version/build, model identifier, battery health, charge %, free disk, room temperature, brightness, charging/network state and debugger attachment. The app logs the model identifier and OS string; other fields require the operator.

Use identical owned/licensed SDR fixtures with a visible timecode/slate and synchronized clap/beep. Keep SHA-256 hashes, durations, codec/pixel/color descriptions, audio sample rate and rotation metadata. With already-installed tools:

```sh
shasum -a 256 /path/to/fixture.mov
ffprobe -v error -show_format -show_streams -of json /path/to/fixture.mov
```

If FFmpeg is unavailable, report that before installing tools. No paid tooling is approved. Never upload personal footage just to get a measurement.

Create one folder per device/run containing the result sheet, JSONL logs, export job marker, project revisions, export metadata and Instruments traces. Keep large evidence out of Git. Include failure attempts, not just successful reruns.

## Build gate

1. Capture `xcodebuild -version`, available SDKs and each phone's exact OS/build.
2. Run `swift test` and the unsigned iOS build in the README.
3. Install through Xcode's existing account signing path. Record failures. A simulator build cannot pass the capture/performance gate.
4. Complete one capture → edit → save → preview → export → reopen smoke run on **both** phones before extended profiling.

## Bounded feature checks

| Area | Trials/checks | Required evidence |
|---|---|---|
| Capture capabilities | Every discovered rear lens, supported focus/exposure; unsupported lens/format/permission combinations | Requested vs applied settings, output metadata; unavailable controls must not claim success |
| Capture reliability | 20 recordings per supported baseline 1080p30 format; permission denied, audio interruption/route change, backgrounding and low-storage cases | Count valid audio/video files; state transitions, errors and original recordings |
| Trim/order/title/audio | Start/length boundary cases, swap twice, nonzero source trim, silent source, portrait/landscape/rotation, 44.1/48 kHz audio | Preview/output comparison with timecode/clap; reject invalid ranges and too-short music |
| Unsupported inputs | HDR, corrupt file, missing source, >10-minute source, >60-second timeline | Visible rejection, no “success” output, original media preserved |
| Offline | Local capture/import/edit/save/reopen/export in airplane mode | Screen notes and logs; no network dependency |
| Export correctness | 20 fixture exports per device | Independent full decode, expected duration within 1/30 s, 1080×1920, correct crop/title/order, A/V offset ≤40 ms |

Inspect exported and original streams independently. For tools already available:

```sh
# Fails on decode errors; does not alone prove sync or visual correctness.
ffmpeg -v error -xerror -i output.mp4 -f null -
ffprobe -v error -show_format -show_streams -of json output.mp4
```

Check A/V offset using matching clap/slate events, not only the first container timestamps. Validate title orientation and position in the exported file against native preview. Check original hashes before/after. A metadata-only pass is not an export-correctness pass.

## Playback, seeks and UI

- Profile a 60-second two-clip/title/source-audio/music project in Release with Instruments. Capture a cold run and a run after 15 minutes of repeated editing/playback/export. Record display cadence/dropped displayed frames, audio drift, stalls, main-thread work and observation method.
- Proposed bounded target: under 1% dropped displayed frames, no sustained A/V drift; p95 main-thread interaction work ≤16.7 ms for a 60 Hz target. Separate a real display trace from AVPlayer state or app UI FPS. If Instruments on your toolchain cannot supply the required counter, leave it unmeasured and return the trace for analysis.
- Run 100 reproducible seeks using the harness, once cold and again warm. The JSONL yields **seek-completion** p50/p95/max only. Measure seek-input → first matching displayed frame separately through an appropriate native display trace/instrumented build. This harness does not currently provide that probe; do not mislabel its completion callback. Return the toolchain details first so display instrumentation can be compiled and validated against that SDK.
- There are no proxies. The blueprint's ≤150 ms cached-proxy target is **not applicable yet**; compare any measured original-media display seek to the ≤500 ms uncached target separately.
- The three-minute/extra-overlay blueprint scenario is **not implemented in this bounded harness** and cannot pass.

## Memory, thermal and battery

1. Capture Allocations/VM and energy/system traces for baseline playback and export. Report peak physical footprint and retained memory after each of five edit/export loops, after the same settling interval.
2. Proposed reference budget: ≤500 MB peak and retained growth <10%; label provisional, not a known property of either phone.
3. Run a 15-minute controlled session; log OS thermal changes and room conditions. No critical state is the provisional gate. The harness stops playback/capture and cancels export when notified of serious/critical heat; record how it behaves and how retry works after cooling. It does not silently lower output quality.
4. Report battery/energy over 20 minutes with fixed brightness, network and charge conditions. OS battery % alone is coarse; do not extrapolate universal battery life.
5. JSONL memory sampling is supplementary: it can miss short peaks and stops while the app is suspended.

## Saved-project recovery — 50 interruption trials per device

Back up the **test-only** app container before fault injection. Do not use valuable media. Killing the app, altering test snapshots or filling test-device storage can destroy unsaved test data; do not delete unrelated files or exhaust storage needed by the OS.

- Alternate force-quit immediately before Save, during Save, after visible “Saved revision N,” during preview preparation and during export. Record the last **acknowledged durable** revision and expected complete edit graph before each kill.
- Reopen, compare revision/order/trim/title/gains/media references, then export again. All acknowledged edits must survive; drafts before Save are explicitly outside the promise.
- At controlled low available storage, attempt import/save/export. Expect an explicit failure without replacing the last valid project. Stop storage pressure if the OS becomes unstable.
- In a copied test container, corrupt the newest revision; restore for testing using Xcode's container tools if supported. The app must clearly report fallback as **RECOVERY FAILURE** and preserve corrupt evidence. A fallback that loses acknowledged edits fails the recovery gate.
- In a separate test copy, remove a managed media file. Reopen must report missing media; export must fail. Restore the original test file and retry. Do not delete originals from a real project.
- Corrupt every test revision: opening must block, not create a fresh project silently.
- Force termination is not a substitute for power-loss durability proof.

## Background export — 10 trials per applicable mode per device

Applicable harness modes: foreground, Home/background, screen lock, explicit cancellation, low resources/thermal interruption. It uses a finite background-task allowance only. Modern continued-processing/GPU entitlement mode is **not implemented and must not be marked passing**.

For each trial record project revision, elapsed time before transition, app lifecycle events, thermal/storage state, output state and independent decode result:

1. Start an export; transition at varied points (early, middle, near completion).
2. Observe whether it completes, cancels/fails honestly, or is interrupted.
3. Reopen after OS suspension/termination. A running marker must become `interrupted`, never `completed`. Partial files are not valid published exports.
4. Retry in foreground and verify output. A retry begins a new job; no partial continuation is claimed.
5. A successful state requires a fully valid output. Recoverable cancellation/failure is acceptable to the background-outcome gate but **does not prove reliable background completion**.

## Decision

Populate `docs/native-experiment-results.md` from collected evidence only. Report each pass/fail/blocked separately, with source traces and trial counts. Do not approve a full product build based on a source handoff, metadata checks, simulator playback or one successful export.
