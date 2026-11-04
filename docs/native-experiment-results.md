# Native experiment — results register

## Current decision: BLOCKED / NOT VALIDATED

Swift native is approved. The user reports an iPhone 16 and iPhone 15 Pro and an Apple account with signing setup still needed, but has explicitly clarified that they **do not have a Mac**. Willingness to follow instructions did not establish Mac access. No alternative build/profiling operator is confirmed. “iOS 27” is reported but exact OS builds are unconfirmed. Build and profiling access are blocked, not merely awaiting test results.

Source preparation is **not** a passing experiment. This workspace is Linux and has neither `swift` nor `xcodebuild`; no physical-device connection exists here. No native compiler output, actual playback/export, Instruments trace or recovery trial has been returned.

| Evidence | iPhone 16 | iPhone 15 Pro |
|---|---|---|
| Exact iOS version/build | Unconfirmed (“iOS 27” reported) | Unconfirmed (“iOS 27” reported) |
| Exact Xcode/SDK | No Mac access confirmed | No Mac access confirmed |
| Signing/install | Not attempted here | Not attempted here |
| Native compilation | The user-reported Codemagic run failed before the Swift tests/build: `/Users/builder/clone/native/CaptureExperiment` was absent | Not run |
| Model/persistence unit tests | Not reached in the reported Codemagic run; CI config exists but has not passed remotely | Not run |
| Capture applied settings/valid recordings | Not measured | Not measured |
| Playback dropped displayed frames/audio drift | Not measured | Not measured |
| Seek-to-displayed-frame p50/p95/max | Not measured; instrumentation pending | Not measured; instrumentation pending |
| Seek-completion p50/p95/max | Not measured | Not measured |
| Main-thread interaction p95 | Not measured | Not measured |
| Peak memory/five-loop retained growth | Not measured | Not measured |
| Thermal states/15-minute session | Not measured | Not measured |
| Battery/energy/20-minute session | Not measured | Not measured |
| Export wall time/correctness/A-V offset | Not measured | Not measured |
| Recovery successes/50 trials | 0 trials run | 0 trials run |
| Background outcomes/10 trials per mode | 0 trials run | 0 trials run |
| Offline workflow | Not run | Not run |

## Honest scope differences from the blueprint

- The experiment is capped at 60 seconds/two clips. The broader three-minute layered-playback gate is untested and cannot be inferred.
- There is no proxy path yet. Cached-proxy seek targets cannot be assessed.
- The probe logs seek completion, not displayed-frame latency; real display timing remains an open instrumentation/validation requirement.
- Background testing covers finite execution with truthful cancellation/interruption, not continued-processing/GPU entitlement mode.
- Project persistence uses a full immutable checksummed revision per explicit semantic Save instead of a separate operation journal plus compacted snapshots. Small bounded graphs make this simpler to inspect during fault injection. No journal pruning or automatic draft saving is claimed.
- The shared title definition is used by a native overlay during preview and Core Animation during export. Visual parity must be checked on device; it is not assumed.
- No hardware floor, product-wide launch scope, paid service or release approval is implied.

## Source-level checks performed here

Executed in this workspace:

- `python3 -m unittest discover -s native/CaptureExperiment/tools -p 'test_*.py' -v`: three log-summary tests passed using synthetic test rows, not device measurements.
- `git diff --check`: passed.
- Scheme XML, project identifier references, permission keys, source-file presence and handoff links: structurally checked with Python; not an Xcode project load/build.
- Root `codemagic.yaml` added for a **manual-only**, unsigned simulator build and Swift package tests. It is configuration, not evidence of a hosted build; costs, source-host connection, Codemagic setup, and workflow execution remain the user's/developer's choice. No signing or physical-device testing is configured.
- The first user-reported Codemagic attempt could not `cd` to `/Users/builder/clone/native/CaptureExperiment` and then reported no `Package.swift`. In this Replit workspace the harness exists at `native/CaptureExperiment/Package.swift` and is present in the checked-out Git tree. Thus, the Codemagic job ran against a checkout that does not contain the harness, or a different checkout root; the native build was not reached.
- The workflow now checks the checkout commit and expected paths, prints any matching paths it can find, and fails explicitly if the harness is absent. This diagnostic edit has not yet been copied into or run by Codemagic.
- The uploaded GitHub `main` archive confirms the cause: no `native/` directory, Swift package manifest, or Xcode project is present anywhere in that archive. Its root YAML is the older configuration without the preflight check. The harness must be transferred to GitHub; changing the working-directory path cannot fix absent source. The current test/build scripts also stop immediately if changing directory fails.

Structural checks can catch missing project files or malformed test data; they do **not** verify Swift compilation, Apple API compatibility, native rendering or device behavior. Swift package tests and the iOS build are still unrun.

## Next required evidence

First use a Codemagic repository/branch that contains both the harness and the updated root `codemagic.yaml`, then rerun the manual workflow. The missing-source error indicates the last Codemagic checkout did not contain the harness. After CI compiles, establish an approved Mac/Xcode/Instruments access path and someone able to connect and profile the physical phones. No paid access or architecture change is authorized. Until those steps are resolved, keep physical-device validation blocked.

1. Exact Xcode/SDK and OS build details, `swift test` output, unsigned native build output.
2. Signing/install outcome and one smoke-run log/export from each phone.
3. Instruments and full protocol results, with failures retained.
4. Implement/validate displayed-frame timing instrumentation against the confirmed toolchain before evaluating seek-display gates.
5. Review actual results and issue a measured go/no-go recommendation. Until then, do not close the validation task as successful.
