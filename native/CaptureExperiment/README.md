# Native capture-to-export experiment

**Status: source prepared; Apple build and physical-device validation BLOCKED by unavailable Mac/build/profiling access.**
No native compilation, device run, export or performance measurement has been performed in this Linux workspace. Do not call this a passing experiment or a finished application.

Swift native was explicitly approved. The user reports access to an iPhone 16 and iPhone 15 Pro but has clarified that they do not have a Mac. Their willingness to follow instructions was not confirmation of Mac access. An Apple account is available; signing requires setup. “iOS 27” is reported but not verified. No purchase or paid build is authorized.

The Mac instructions below are a future handoff, not steps the user can execute with their current hardware. First establish access to a Mac with compatible Xcode and Instruments, or a collaborator who can build and profile on the physical phones. Cloud compilation alone would not supply the required device profiling evidence. Do not switch to Expo or commission paid infrastructure without approval.

## Included, and intentionally not included

- Xcode iPhone harness; Xcode 16+ project format; iOS 17 API floor **for this experiment only**, not a product support commitment.
- Capability-discovered rear lenses; only a discovered 8-bit SDR 1920×1080/30 format is enabled. H.264 movie capture, microphone, supported manual focus/ISO/shutter and 30-second recording cap.
- Managed local imports, exactly two video clips, frame-based trim, swap order, one static centered title, source audio and one music track.
- Native AVPlayer/composition preview and portrait 1080×1920/30 Rec.709 MP4 export. Aspect-fill crops the source; no hidden stretch. HDR is rejected explicitly. Music shorter than the timeline is rejected, not silently looped.
- Explicit Save and save-before-preview/export. Unsaved drafts are labeled and are **not** promised to survive termination.
- Checksummed, immutable full-revision journal, atomic file writes, synchronized file handles and read-back verification. Corrupt newest revision recovery is a prominently reported failure, not a silent success. Originals and journal history are retained.
- Finite background execution allowance, cancel and relaunch interruption detection. No continued-processing entitlement, background GPU promise or resume-after-kill promise.
- Local JSONL diagnostic logs, 1 Hz memory/thermal/battery samples, export wall time, 100 deterministic AVPlayer seek-completion probes.
- Foundation-only persistence/model tests via Swift Package Manager.

Not included: the full editor, polished product UI, proxy generation/cache, a three-minute timeline, transitions, photo editing, AI, an Expo bridge, cloud service, paid integration, App Store release or TestFlight setup.

## 1. Confirm the toolchain without buying anything

On the Mac:

```sh
xcodebuild -version
xcodebuild -showsdks
xcrun devicectl list devices
```

On **each phone**, open Settings → General → About → iOS Version and record the version **and build number**. Also record the model, battery health, free storage and whether the OS is beta. Do not substitute “latest.”

If Xcode cannot support the installed iOS version, stop and return its diagnostic. Do not downgrade devices, enroll in paid programs or change the OS as part of this task without approval.

## Codemagic option: unsigned build only

The repository-root `codemagic.yaml` contains a **manual-only** Codemagic workflow. It runs the Foundation-only Swift package tests and compiles an unsigned iOS Simulator `.app`; it has no automatic push trigger, signing, publishing, or physical-device test. Codemagic's docs state that workflows without triggering events can be started manually. Check the current service cost before starting any hosted build; adding the file itself starts nothing.

To use it, put this repository in a source host accessible to your Codemagic account, add the repository in Codemagic, and manually start `Capture experiment — tests and unsigned simulator build`. The workflow artifacts include test/build logs and the simulator `.app`. A simulator binary cannot be installed on an iPhone. The workflow is not a replacement for the device and Instruments protocol below.

If Codemagic reports that `native/CaptureExperiment` or `Package.swift` is missing, its checked-out repository/branch does not include this harness (or the harness was moved). Confirm the selected repository and branch contain both `native/CaptureExperiment/Package.swift` and `native/CaptureExperiment/CaptureExperiment.xcodeproj`. The workflow now prints the checked-out commit and nearby matching paths before exiting with a specific error; it will not silently skip tests and return a misleading green build.

For actual-phone installation and testing, a developer must set up an approved iOS signing/provisioning path; Codemagic's iOS signing docs state that signing requires Apple Developer Program membership. No Apple keys, certificates or paid membership are configured here. Instruments profiling of the two physical phones still requires someone with Mac/Xcode access connected to those phones.

## 2. Open and sign locally

1. Copy this repository to the Mac, preserving `native/CaptureExperiment`.
2. Open `CaptureExperiment.xcodeproj`, not the package, to run the iPhone app.
3. Select the **CaptureExperiment** target → Signing & Capabilities. Keep automatic signing, select your existing Apple team, and set a unique bundle identifier if Xcode requests one.
4. Connect and trust the phone. Enable Developer Mode if prompted, then select the physical phone as the run destination.
5. Try the existing account's available signing path. If Xcode asks for paid enrollment or an unavailable entitlement, stop and send the error. This experiment does not require purchasing a service in advance.
6. Build and run. Allow camera and microphone access. Do not add background audio capabilities to keep the app alive.

**Do not share passwords, signing certificates, provisioning profiles or account tokens.** Signing changes stay local in Xcode.

## 3. First build checks

From this directory on the Mac:

```sh
# Pure project-format/persistence tests; no phone or signing required.
swift test

# Compile the complete iOS app without signing. This is NOT a device test.
xcodebuild -project CaptureExperiment.xcodeproj \
  -scheme CaptureExperiment -configuration Debug \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Return complete compiler errors if either fails. Source has not been compiled here; these are required gates, not commands already known to pass. No simulator screenshot or web preview substitutes for them.

## 4. First end-to-end smoke run on each phone

Use only your own or licensed, non-sensitive media. Disable HDR in fixture capture settings; files must be downloaded locally before offline testing.

1. Start the camera. Verify the lens list reflects actual hardware; unsupported controls must be absent. Apply focus/ISO/shutter and note the **applied** values reported by the camera, not only the requested slider positions.
2. Record a clip, letting the 30-second cap finish it. Import a second SDR fixture of at least 35 seconds from Files. Use clear motion, a visible clock/slate and a synchronized clap/beep in your fixtures.
3. Trim by editing start/length in **30 fps frames**. For a first trimmed example, use 750 frames (25 seconds) from the captured clip and 1,050 frames (35 seconds) from the fixture: 1,800 frames = 60 seconds. If capture is slightly short, use its actual source length. Swap the clips and confirm order.
4. Add a title and music of at least 60 seconds. Save. Record the acknowledged revision shown in the UI.
5. Prepare preview. Check portrait framing, title placement, clip boundary, source audio and music. Play and seek. Run the 100-seek probe.
6. Export. Share the MP4 and current measurement log. Export completion only checks dimensions/duration; independent decode, A/V sync and visual correctness are still required.
7. Force-quit after an acknowledged Save; reopen. Confirm revision, title, gains, order and trims. Export again and compare decoded content and metadata; do not require byte-identical MP4 containers.
8. Repeat in airplane mode with already-local fixtures.

For profiling use **Product → Profile** (Release build) and record whether the debugger is attached. Keep debug and release measurements separate.

## 5. Evidence collection and full protocol

Follow [`../../docs/native-experiment-validation.md`](../../docs/native-experiment-validation.md).
Fill in [`../../docs/native-experiment-results.md`](../../docs/native-experiment-results.md); its current values are deliberately “not measured.”

Retrieve the app's `Documents/Experiment` folder with Finder's app file sharing or Xcode → Devices and Simulators → select device → installed app → download container. It contains:

- `Media`: managed originals; do not delete before collecting recovery evidence.
- `Revisions`: checksummed full-revision journal.
- `Exports`: completed and potentially interrupted partial output. Only `export-job.json` with `state: completed` identifies the published result.
- `Logs`: one JSONL log per launch.
- `export-job.json`: export outcome or interrupted-job evidence.

Store large traces, MP4s and app containers outside Git, for example under the ignored root `generated-artifacts/` directory. Do not commit personal media or signing files. Logs may contain local media names and system diagnostics; inspect before sharing.

## Measurement limitations

- `seekCompletion.latencyMilliseconds` measures AVPlayer's completion callback, **not** first displayed matching frame. No proxy cache exists; do not call a second pass “cached-proxy” performance.
- `physicalFootprintBytes`/`sampledPeakBytes` are 1 Hz samples. Instruments Allocations/VM is needed for actual peak/growth analysis.
- Player start/pause logs are not dropped-frame counters. An Instruments/video-display trace is required; if a tool cannot expose the measure, record “unavailable,” not zero.
- Backgrounding/locking may let a small job finish, cancel it, suspend it or terminate it. Expiration requests cancellation. On relaunch, a running marker becomes interrupted. Retry is a new export, not a resume.
- The 60-second harness cannot satisfy the blueprint's proposed three-minute layered-playback gate. Measure this bounded case only and leave the broader gate untested.
- Snapshot tests do not prove durability under sudden power loss. Device termination, storage pressure and corruption trials remain mandatory.

## Return first

Send the exact Xcode version and both OS builds, the output of `swift test` and the unsigned build, and any signing error. After the first successful device smoke run, return its log and output checks. The task remains open until both devices' measurements and failures have been reviewed.
