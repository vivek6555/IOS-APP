# iOS Creative Studio — Feasibility Blueprint

Planning status: ready for product review, not approved for implementation.
Research date: 2 November 2026.

**Experiment approval update:** The user subsequently approved Swift native for the bounded experiment and reported an iPhone 16 and iPhone 15 Pro. They explicitly clarified that they do not have a Mac; willingness to follow instructions was not confirmation of build access. An Apple account is available but signing needs setup. Build/profiling access is blocked and exact OS builds remain unconfirmed (“iOS 27” reported). This does not approve the full product. See [the current evidence register](native-experiment-results.md) and [native handoff](../native/CaptureExperiment/README.md). No native device validation has yet been completed. The comparisons and estimates below retain their original planning context.

## 1. Executive decision

The confirmed first audience is **short-form social creators**. The user wants a comparison before choosing native Swift or Expo. Hardware access, budget and timeline are unknown. No minimum iPhone or iOS version has been approved.

Recommend a native Swift media engine regardless of interface choice. Prefer a SwiftUI/UIKit interface for an iOS-only team. Choose Expo plus custom Swift modules if a React Native-skilled team or committed Android roadmap makes shared interface development valuable. Expo is a native application framework, not a WebView; nevertheless, Expo Go cannot run arbitrary custom Swift modules [S1].

Do not select Expo just to obtain a quick preview: that preview would not validate the core technical risks. Do not treat a native Swift choice as a ban on using Replit for source authoring and planning.

The differentiated workflow is: **capture or import → edit a reusable master → adapt framing and captions → export several social formats**. Competing on the number of effects is a weaker initial proposition.

### Proposed launch boundaries, not commitments

- Local-first, account-free editing of short projects, initially up to three minutes.
- One primary video track, one overlay track, source audio, one music track and one voiceover track.
- Reliable SDR 1080p export first; 4K export gated by hardware experiments.
- All four requested aspect ratios; photo adjustments and cover creation.
- Dedicated useful camera workspace, but defer specialist RAW and advanced capture analysis.
- Caption editing/import in the core; automatic transcription gated by language, device and accuracy tests.
- No cloud backup, social account integration, generative video or unlimited AI at launch.

These restrictions control decoder count, memory, thermal load and testing scope. They should appear honestly in product messaging.

## 2. Swift versus Expo comparison

| Criterion | SwiftUI/UIKit + Swift engine | Expo/React Native + Swift engine |
|---|---|---|
| Camera/rendering reach | Direct Apple API access | Same native potential through custom modules and native views |
| Professional timeline | UIKit or purpose-built native view | Native view for frame-critical interactions; React Native for surrounding controls |
| Implementation languages | Swift plus optional Metal shaders | TypeScript, Swift and optional Metal shaders |
| Frame transport | Stays native | Must also stay native; JS exchanges commands and metadata, not video frames |
| Build/test | Apple toolchain and device testing | Custom development binary; Expo Go insufficient [S1–S2] |
| Local debugging | Xcode and Instruments | Xcode/Instruments plus React Native diagnostics |
| Android reuse | Limited UI reuse | UI/domain reuse possible; Android media engine still separate |
| Dependency risk | Apple SDK migrations | Apple SDK plus Expo/RN/native-module compatibility |
| Best fit | iOS-first professional product | Existing RN team, meaningful cross-platform business case |
| Main danger | Underestimating media-engine scope | Mistaking faster UI development for faster media engineering |

**Recommendation remains conditional.** With no known team or Android requirement, Swift is simpler to maintain. Expo is technically credible, not rejected; the selection needs an explicit approval.

If Expo is chosen, keep the engine as an independently testable Swift package. Expose project operations, capability queries, cancellation, progress and native preview surfaces through a thin local Expo module. Coalesce preview updates; tag commands with project revision IDs to reject stale results. Keep capture sessions, audio clocks, compositing and timeline playback native. Use config plugins for reproducible native configuration rather than fragile edits to regenerated Xcode projects [S1].

### Tooling responsibilities

Replit supports source development, planning, backend work, Expo UI work and documented mobile preview/publishing flows [S9]. It does not provide a local macOS/Xcode environment. Do not infer support for this project's custom development-client workflow from the availability of a stock Expo preview.

Expo documents EAS cloud compilation of custom development builds from non-macOS hosts [S2]. Cloud compilation can avoid owning a Mac for compilation alone; it does not replace local Instruments profiling or real-device tests. Plan access to a Mac/Xcode environment for professional native engineering and at least two physical iPhones before claiming feasibility. Verify the custom-client connection and signing workflow separately before choosing it.

No accounts, integrations, purchases or cloud builds have been configured in this task.

## 3. Architecture

### Shared services

1. **Asset store:** imports managed copies, tracks metadata and source permissions, handles missing/offloaded media, provides relink and cleanup.
2. **Project store:** authoritative edit graph, undo/redo commands, durable journal, atomic snapshots and migrations.
3. **Render planner:** translates an immutable project revision into preview or export instructions.
4. **Media engine:** AVFoundation composition/capture/encoding, Core Image processing, Core Video buffers and selective Metal effects.
5. **Analysis workers:** thumbnail, waveform, caption, beat and scene analysis with bounded concurrency.
6. **Export coordinator:** validates settings, checks space, tracks jobs, handles cancellation/interruption and atomically publishes successful output.
7. **Capability service:** device/OS/format/model availability, never a hardcoded “Pro phone” boolean.

SwiftUI handles library, settings and ordinary controls; UIKit is available for high-density timeline gestures. Use structured concurrency and explicit ownership: serialize camera configuration and project commits; keep decode/analysis/export off the main thread. Do not make all rendering concurrent without a memory budget.

### Project format

Use a versioned document directory, conceptually:

- Manifest: schema version, project ID, revision, timestamps, canvas dimensions, rational frame rate, working color space.
- Assets: stable IDs, relative managed paths, fingerprints, codec/duration/orientation/color metadata, optional Photos identifiers for provenance.
- Edit graph: tracks, clips, rational source and timeline ranges, speed mapping, transforms, effect parameters, blend mode and layer order.
- Text/captions: text, timed segments, style, font reference and accessibility text.
- Audio: clip offsets, trims, gain automation, mute, fades and channel information.
- Photo operations: ordered adjustments, masks, layers and RAW-development parameters where supported.
- Format variants: master revision plus per-format reframing and title/caption positions.
- Journal and recoverable snapshots.
- Disposable cache references: proxy, thumbnails and waveform data, keyed by source fingerprint and processing version.
- Export records: revision, settings, status and successful output reference.

Never store absolute sandbox paths as the sole asset identity. A project references immutable originals; an export is a new asset. Imported Photos media may require downloading from iCloud, so “offline” begins after media and optional models are locally available.

### Save and recovery contract

Journal each completed semantic edit before displaying “Saved”; debounce large snapshots. Commit snapshots with atomic replacement and checksums. Keep a prior valid snapshot until the new one is verified. Undo does not delete original media. On startup, replay valid journal entries after the latest snapshot; isolate corrupt entries and offer recovery rather than silently resetting.

Autosave cannot guarantee zero loss during storage failure or interrupted uncommitted gestures. Promise recovery of acknowledged durable edits and show failure visibly. Do not delete managed originals while any project references them. Separate cache cleanup from project/media deletion with clear confirmation.

## 4. Media-engine design

### Video

AVFoundation composition supports time-based transformations; custom AVVideoCompositing provides source pixel buffers for custom effects [S3]. Start with built-in composition where sufficient. Adopt a custom compositor for masks, nonlinear grading and combinations that cannot share the simpler pipeline.

Use CMTime-style rational timing, not accumulated floating-point seconds. Preserve source timing; normalize the chosen output rate explicitly. For variable-frame-rate clips, use presentation timestamps and test audio synchronization.

Interactive preview uses proxies and reduced render resolution. Final export uses originals. Both consume the same edit graph and effect definitions; neither uses UI screen capture. Exact pixel identity across proxy and full-resolution output is not assumed, especially for nonlinear filters and scaled masks.

Decode only necessary time windows. Reuse bounded pixel-buffer pools and GPU contexts. Cancel obsolete seeks, requests and analysis. Model decoder count and transitions explicitly: a single transition may require two source decodes.

Reverse requires a bounded preprocessing/cache strategy; never load an entire long clip into RAM. Slow motion does not imply AI frame interpolation. Source audio and time stretching require separate quality tests.

Audio uses the media clock, explicit mixing, gain/fades, waveform caches and latency-aware voiceover alignment. Prevent clipping or offer a measured limiter rather than silently normalizing every mix.

### Photo

Core Image provides a non-destructive filter graph, with Metal kernels only when required. Apply geometry, color, masks and compositing in a defined order. Preview at reduced size; export from originals at requested dimensions. Tile high-resolution operations where valid, with overlap for filters that sample neighboring pixels.

Keep RAW data intact; develop to the working color space for adjustments. Do not label a processed JPEG “RAW export.” Preserve or intentionally remove metadata; default exported location metadata off, with a user option. Before/after uses matching geometry or clearly signals the difference.

### Color and output

Launch target: explicit SDR Rec.709 video and defined sRGB photo output. HDR imports require validated tone mapping with a warning; if that path fails validation, reject HDR editing rather than silently clipping highlights. Preserve originals regardless. Wide-gamut/HDR editing and export become a later tested capability.

Offer H.264/AAC MP4 for compatibility; evaluate HEVC separately. Export settings include dimensions, frame rate, color policy and bitrate/quality. A high bitrate is not a guarantee of fidelity. Validate duration, audio sync, orientation and color metadata on independently decoded output.

### Background work: corrected current guidance

iOS 26+ introduces BGContinuedProcessingTask for user-initiated jobs that begin in the foreground and continue in the background [S5–S6]. Apple explicitly lists video export. GPU use requires supported resources and the Background GPU Access entitlement. Report real progress and handle queue/rejection, cancellation and expiration.

On older OS versions, plan foreground export with limited background continuation, not unlimited execution. On all versions, preserve project state and identify interrupted exports. Initially restart incomplete exports safely; resumable segmented rendering is a separate feature, not inherent in AVAssetExportSession. Never promise work continues after force-quit or resource termination.

## 5. Complete requested-feature disposition

Legend: **L** proposed launch; **E** expansion after launch; **R** research-gated.
All ordinary editing is local/offline after required assets are imported. “Device” means runtime capability and hardware testing; it is not a shipping guarantee.

### Video

| Requested features | Stage | Approach / constraint |
|---|---|---|
| Multi-track video/audio, picture-in-picture | L bounded; E expanded | AV composition/native compositor; initial track budget above |
| Trim, split, merge/reorder | L | Non-destructive timeline operations |
| Crop, rotate | L | Render transforms, orientation tests |
| Speed, slow/fast motion | L basic; E advanced | Time mapping; no promised optical-flow interpolation |
| Reverse | E | Windowed decode and derived media cache |
| Keyframe animation | E | Versioned curves on effect/transform parameters |
| Transitions, cinematic effects | L dissolve; E library | Native compositing; benchmark concurrent decodes |
| Exposure, contrast, saturation, highlights/shadows, grading | L basic; E advanced | Shared color graph |
| LUT support | E | Validated LUT parser, color-space handling and licensing |
| Chroma key | E | GPU effect plus spill cleanup controls |
| Masking and blending | E | GPU masks, compositing semantics |
| Text, titles, captions/subtitles | L static/timed; E animated | Editable text/timing; licensed fonts; caption import |
| Music, voiceover, sound effects | L user media | Native recording/mixing; no bundled unlicensed music |
| Waveforms and volume | L | Cached analysis and gain controls |
| Capture stabilization | L Device | Supported capture modes; framing/latency changes disclosed |
| Post-production stabilization | R | Motion estimation, crop cost, rolling shutter; no universal promise |
| Video background removal | R | Segmentation plus temporal consistency; quality/heat gates |
| High-quality export, saved projects/resume | L | Native output, atomic persistence, interruption recovery |

### Photo

| Requested features | Stage | Approach / constraint |
|---|---|---|
| Crop, resize, rotate | L | Non-destructive geometry |
| Perspective correction | E | Geometric warp, defined edge handling |
| Exposure, brightness, contrast, color | L | Core Image adjustment graph |
| HSL, curves, professional grading | E | Color graph; precision and color tests |
| Filters, customizable presets | L simple; E advanced | Serializable parameter recipes |
| AI background removal | E Device | Vision foreground mask [S7]; inspect edges and supported subjects |
| Object removal and retouching | E manual; R generative | Local clone/heal first; model/cloud inpainting later |
| Portrait enhancement | E | Reversible subtle adjustments; no inferred personal identity |
| Blur/depth effects | E Device | Actual depth data when present; label estimated masks as estimates |
| Text, stickers, shapes, overlays | L cover text/shapes; E library | Editable assets with license tracking |
| Layers/masking | E | Layer graph and mask storage |
| Before/after | L | Consistent framing and adjustable comparison |
| High-resolution export | L tested limits | Full-resolution render; bounded memory and explicit output dimensions |

### Social studio

| Requested features | Stage | Approach / constraint |
|---|---|---|
| Reels, Stories, posts, Shorts, TikTok-style video | L | Format presets and share sheet; not automatic platform publishing |
| 9:16, 4:5, 1:1, 16:9 | L | Canvas variants retaining master edits |
| Platform export presets | L | Versioned presets; recheck platform restrictions before release |
| Covers/thumbnails | L | Frame extraction plus photo/text editing |
| Ready-made/reusable templates | L small licensed set | Declarative layouts, not executable downloaded code |
| Carousel designs | E | Linked pages, consistent style and ordered export |
| Animated text/subtitles | E | Timing and native render support |
| Automatic captions | L candidate / R gate | Editable transcript; languages, model availability and accuracy tested |
| Music synchronization and beat detection | E | Local audio analysis plus user-correctable markers |
| Brand kits | E | Fonts, colors, logos; rights and font availability checked |

### Professional camera

| Requested features | Stage | Approach / constraint |
|---|---|---|
| Dedicated capture interface, live recording info | L | Native preview; elapsed time, actual configuration, storage and warnings |
| Manual focus, ISO, shutter, white balance | L Device | AVFoundation mode/range queries; configure serially [S4] |
| Exposure compensation | L Device | Meaningful in auto modes; do not imply independent auto compensation in fully manual exposure |
| Focus/exposure lock | L Device | Confirm applied device state and show lock state |
| Manual lens selection | L Device | Discover cameras; unsupported mid-recording switches disabled |
| Frame rates 24/25/30/60/higher, 4K | L supported basics; E high rate | Query selected format's supported rate ranges; validate combinations |
| Stabilization options | L Device | Show supported modes, not fake controls |
| Grid, level, timer | L | UI overlay, motion data, cancellable capture countdown |
| Burst | E | Capture readiness/backpressure; no arbitrary burst-rate claim |
| High-resolution photo capture | L Device | Supported photo dimensions; memory and processing latency |
| Histogram, focus peaking | E | Downsampled native frame analysis; avoid capture starvation |
| RAW/ProRAW | E Device | Query photo output, retain DNG and processed companion [S8] |
| Audio input selection | E Device | AVAudioSession route availability; handle disconnect/interruption |

RAW and ProRAW are not synonyms. Apple documents different processing and capture constraints; query availability after configuring the session [S8]. Do not publish a static per-model feature chart until measured.

### Advanced AI

| Requested feature | Proposed stage/location | Acceptance and cost implications |
|---|---|---|
| Automatic video editing | E local orchestration | Suggest reversible cuts; never replace the master silently |
| Smart highlights, intelligent scene detection | E local models/heuristics | Human review; evaluate on creator footage, not generic demos |
| Automatic captions | Research local first; opt-in cloud alternative | Language/device/model coverage and timestamps; manual correction required |
| Background removal | E stills local; R video | Fine hair, transparent objects, motion and temporal stability |
| Object removal | R local or cloud | Content reconstruction can be wrong; keep original and mask |
| AI enhancement and color correction | R local model or cloud | Avoid hallucinated detail and skin-tone bias; compare before/after |
| Beat synchronization | E local DSP | Often does not need an LLM; user-adjustable beat grid |
| Text-to-video, image-to-video | R cloud initially | High/variable per-output cost, upload policy, provenance and moderation |
| Voice cleanup | R local model or cloud | Speech distortion tests, licensing and latency |
| AI-generated templates | E cloud optional | Generate validated layout data; never execute model-supplied code |

No provider or price is approved. On-device does not mean zero engineering cost, zero energy cost or no initial model download. Cloud costs require a selected model and quality benchmark; unsupported numerical vendor claims are intentionally omitted.

## 6. Camera capability strategy

Discover camera devices and supported formats, then create a capability snapshot for the selected lens, resolution, FPS and session outputs. Include OS availability, focus/exposure/WB modes, ISO/shutter ranges, photo dimensions, RAW formats, stabilization, audio route and system pressure.

Query again after configuration changes. Apply settings under configuration lock, release promptly and display actual applied values [S4]. A supported feature may become unavailable with a different output or format. Explain disabled controls. Do not silently switch resolution or FPS to satisfy another setting.

Use permission requests at the point of use; microphone denial must permit silent recording if selected explicitly. Handle camera interruption, incoming calls, route changes, storage exhaustion and thermal pressure. The UI may warn or stop gracefully but must never claim capture is active after the session stops.

## 7. Navigation and design specification

- Projects: recent work, import, search, duplicate, rename, recovery, delete and storage management.
- Create: Video, Photo and Social starting points; aspect ratio and template selection.
- Camera: independent photo/video workspace; capture settings and last capture.
- Settings: default formats, storage, accessibility, privacy, purchases and help.
- Video editor: native preview, timeline, contextual tool controls, undo/redo, captions and export.
- Photo editor: before/after, adjustment groups, crop, presets and export.
- Export: actual dimensions/frame rate, estimated size, color policy, progress, cancel, failure/retry and share.

Keep the requested elegant dark workspace, readable typography and consistent gestures. Use original branding, accessible contrast, Dynamic Type where workable, VoiceOver labels and reduced-motion support. Numeric entry and buttons supplement gestures. A professional camera remains a primary destination even when its specialist functions arrive later.

Usability target: a first-time short-form creator can import three clips, trim them, add text and export a vertical video without assistance. Validate with 5–8 representative creators before expanding the feature inventory.

## 8. Privacy, storage and business

Keep originals, edit graphs and analysis on device by default. Ask separately before uploading media/audio; explain provider, processing purpose, retention and expected charge. Use authenticated short-lived upload access, server-side provider credentials and per-user quotas if cloud features are later approved. Avoid logging media, transcript bodies, faces, signed URLs or private filenames.

Cloud jobs need cancellation, idempotency, retry limits, budget caps and deletion handling. Cancellation may not refund provider compute already used; disclose this. Provider retention/deletion terms must be verified before launch. Device file protection, privacy manifests and relevant permission descriptions require release review.

Free tier: useful local editing and export. Paid tools: advanced grading, layers, templates and workflow features. Optional bounded AI credits fund variable-cost processing. A one-time offline tools purchase is possible; do not sell lifetime unlimited cloud inference. Subscription value must recur beyond merely preserving access to users' projects.

No cloud storage is required at launch. If later added, measure storage, egress and sync-conflict costs before promising backup. Secure backups and project portability are distinct from regenerable caches.

App Store work includes signing, TestFlight, privacy disclosures, purchase/restore behavior, account deletion if accounts are introduced, rights-cleared music/fonts/templates/models and current policy review. Do not assume subscriptions or cloud AI use external web checkout; validate applicable storefront policies when monetization is implemented.

## 9. Hardware validation plan

All numbers below are **proposed acceptance targets, not measured results**. No native app, simulator, device or export has been tested.

### Device matrix

Select an oldest supported non-Pro iPhone, a representative middle-generation device and a recent Pro device. At least two physical devices are required for the first experiment; three for release gating. Test the eventual minimum OS and latest stable OS; explicitly test iOS 26 background behavior when available. Choose the minimum OS only after device availability and audience coverage are known.

Fixtures: owned/licensed 1080p30/60 and 4K30/60 clips; variable FPS; HDR; rotation metadata; silent clips; 44.1/48 kHz audio; portrait stills; large HEIF/JPEG; available RAW; missing media; corrupt input; low storage. Record device, OS, battery health, thermal state, storage, app revision and fixture hash with results.

| Area | Proposed pass gate | Method |
|---|---|---|
| Playback | Under 1% dropped displayed frames in a 3-minute 1080p30 project with one primary clip, overlay, title and two audio layers; no sustained audio drift | Native timing counters + Instruments; test cold and after 15-minute session |
| Scrubbing | p95 cached-proxy seek-to-display ≤150 ms over 100 seeks; uncached ≤500 ms target | Timestamp input and displayed matching frame; report cold/cache separately |
| UI | p95 main-thread interaction work ≤16.7 ms on a 60 Hz target | Instruments; no inference/render work on UI thread |
| Export correctness | 20/20 fixture exports decode fully; duration within one output frame; A/V offset ≤40 ms; correct orientation/dimensions | Independent decode, timestamp inspection, visual color fixtures |
| Export speed | Target ≤2× project duration for baseline 1080p30 fixture on minimum device; 4K measured separately | Wall time, peak memory and thermal trace; speed misses do not justify degraded hidden quality |
| Memory | Provisional baseline peak ≤500 MB, no memory-pressure termination; after five edit/export loops retained growth <10% | Instruments allocations/VM; refine budget by selected device and capabilities |
| Thermal | No critical thermal state in baseline 15-minute session at controlled room temperature; adapt at serious state | OS thermal/pressure events; log preview quality changes and recovery |
| Battery | Report percentage and energy use during controlled 20-minute workflow; establish per-device budget after baseline | Same brightness/network/charge conditions; no universal battery-life claim |
| Recovery | 50 interruption trials recover all edits previously acknowledged durable; zero unreadable projects | Force termination around journal/snapshot boundaries; test low storage and corrupt snapshots |
| Background export | 10 trials per applicable mode yield valid output or truthful recoverable cancellation/failure; no corrupt “success” | Foreground/background, lock, cancel, resource pressure; GPU support/entitlement cases |
| Camera controls | Every enabled control maps to supported applied values; unsupported combinations never shown as working | Compare reported configuration and captured metadata; all lenses/selected formats |
| Capture reliability | 20 short recordings per supported baseline format with valid audio/video and no false recording state | Permissions, interruption, route loss, low-space cases included |
| Photo | Export dimensions correct; originals byte-identical; before/after and output match intended adjustment within agreed color tolerance | Hash originals; color-managed reference comparisons; large-image memory test |
| Privacy/offline | Core import-local/edit/reopen/export works without network; no media leaves device without opt-in | Network capture + airplane-mode run with downloaded fixtures/models |

Performance failures trigger explicit scope reductions (fewer tracks, proxy size, supported formats) or a higher device floor, not hidden fallbacks. Define color tolerance and battery budgets after selecting hardware and calibrated fixtures.

## 10. Roadmap, staffing and economics

Durations are rough elapsed ranges for a capable small team with overlapping work, not a quote or a schedule commitment.

| Phase | Deliverables / exit gate | Dependencies and main risks | Complexity / range |
|---|---|---|---|
| 1. Architecture/feasibility | This blueprint, architecture decision, native capture/edit/export experiment | Hardware, staffing and signing access; hidden API/format constraints | High; 2–4 weeks including experiment |
| 2. UX/design system | Validated creator workflow, component language, accessibility and error/recovery states | Phase 1 constraints; timeline usability | Medium; 3–5 weeks |
| 3. Camera | Capability-driven capture, manual basics, stable saved media | Native experiment, devices; heat/interruption and format combinations | High; 6–10 weeks |
| 4. Video engine | Durable projects, bounded timeline, native preview, audio and tested export | Asset/project store and rendering; sync/color/memory | Very high; 12–20 weeks |
| 5. Photo engine | Adjustment graph, comparison, cover tools, tested high-res output | Shared assets/color; memory and metadata | High; 6–10 weeks |
| 6. Social studio | Format variants, presets, small template set, caption editing | Working engines; inconsistent platform requirements/licensing | Medium–high; 4–8 weeks |
| 7. AI | Benchmarked selected tools, consent, cost caps and reversible results | Local model/provider evaluation; quality, privacy and unit economics | High; 6–12+ weeks |
| 8. Release hardening | Device gates, recovery, accessibility, TestFlight, review readiness | Launch features; regressions and store approval | High; 6–10 weeks |

Performance and recovery testing start in phase 1 and continue throughout. Phase 8 is not the first test phase. For the creator launch, prioritize photo cover tools and social ratios early; full RAW, retouching and generative tools need not block release. A polished interface prototype is explicitly not a completed editing app.

Suggested team: one senior iOS/media engineer, one additional app/media engineer, a product designer with mobile editing experience, and fractional-to-full-time QA/performance support. Expo requires React Native expertise as well as Swift expertise; it does not replace the media engineer. Cloud features add backend/privacy work.

A focused release is plausibly 6–12 months for roughly 3–5 contributors. Broad professional parity may require 18–30+ months. Unknown team skill and scope create substantial uncertainty; re-estimate after the native experiment.

### Budget model (USD, illustrative assumptions)

- Focused feasibility experiment: 4–8 person-weeks. At $2,000–$4,500/person-week, approximately $8,000–$36,000, before hardware/accounts. This is not a market quote.
- Example focused product: 24 person-months × $8,000–$18,000 fully loaded/person-month = $192,000–$432,000.
- Hold 20–30% contingency for hardware-specific issues, media correctness and scope discovery; avoid counting it as an approved budget.
- Local-only media processing can have zero per-export cloud compute charge. Supporting service allowance: $50–$300/month for an early pilot, excluding cloud media/AI, developer accounts, CI and vendor plan changes; this is not a Replit pricing quote.
- Obtain current quotations for Apple enrollment, Mac access, test phones, build services, licensed media and selected AI providers before purchase.

AI monthly cost = active AI users × jobs/user × billable units/job × unit price + retries + storage + egress.

Illustrative sensitivity, not provider pricing: 1,000 users × 20 caption minutes × an assumed $0.01/minute = $200/month before overhead. 1,000 users × 2 generated clips × an assumed $1/clip = $2,000/month. Actual models can be materially more expensive or cheaper. Benchmark success rate and cost per accepted result, not only advertised unit rates.

## 11. First native experiment for approval

After choosing the interface route and obtaining a build/device path:

1. Build a minimal native engine harness, not a polished app. Capture 30 seconds at a supported format with manual exposure/focus and discover unsupported combinations honestly.
2. Import that clip and a second fixture, trim/reorder, add one text overlay and one music track, preview at 1080p and export a 60-second 9:16 project.
3. Save, terminate, reopen and export again; compare revision, duration and output. Test low storage, missing media and cancellation.
4. Profile playback, scrub latency, memory, thermal behavior and foreground/background export on the available minimum and higher-end devices.
5. If Expo is selected, embed the same native engine and preview in a custom development build and confirm no per-frame JS transport.
6. Deliver actual measurements, failures and a go/no-go recommendation. If hardware is unavailable, source work may be prepared but the experiment remains unvalidated; do not mark it as passing.

Success permits the limited product build, not a claim that every requested feature is feasible. Failure produces a narrower scope/device floor proposal before further investment.

## 12. Decisions awaiting approval

| Decision | Proposed default | Status |
|---|---|---|
| First audience | Short-form social creators | Confirmed by user |
| Swift versus Expo/native | Swift for iOS-only; Expo if team/platform case justifies it | Swift native approved for the bounded experiment |
| Launch feature/track/duration limits | Boundaries in section 1 | Proposed |
| Minimum iPhone/iOS | Choose after access and target-audience review | Unknown |
| Mac, devices, Apple account/build access | Identify before native experiment | iPhone 16/15 Pro and Apple account reported; user has no Mac; build/profiling access blocked, signing not configured |
| Staffing, spending cap and release date | Approve experiment first; re-estimate from evidence | Unknown |
| Caption languages and offline model requirements | Start with a small explicitly selected language set | Unknown |
| Monetization | Useful free core; paid tools; metered cloud AI | Proposed |

Hardware, budget and timing being unknown does not prevent this planning deliverable. It does prevent an honest promise of implementation dates or validated native performance.

## 13. Research evidence and limitations

Official documentation was read for architecture-critical claims. API existence is not evidence of sustained performance or feature quality. No code or device tests were performed. Cost and performance figures above are labeled assumptions/targets, not benchmark results.

- **S1 — Expo, Add custom native code:** https://docs.expo.dev/workflow/customizing/ — Expo Go restriction, Swift/Kotlin modules, local modules, config plugins and native debugging.
- **S2 — Expo, Development builds:** https://docs.expo.dev/develop/development-builds/introduction/ — custom binaries, local versus EAS cloud builds, signing and device installation.
- **S3 — Apple, AVVideoComposition:** https://developer.apple.com/documentation/avfoundation/avvideocomposition — composition transforms and custom compositor pixel buffers. Current docs include newer configuration/async APIs and deprecated older overloads; implementation must check availability against the chosen deployment target.
- **S4 — Apple, AVCaptureDevice:** https://developer.apple.com/documentation/avfoundation/avcapturedevice — capability queries, configuration locking, focus/exposure/WB, formats and pressure monitoring.
- **S5 — Apple, Long-running tasks:** https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados — user-started video export, GPU support/entitlement, progress, cancellation and resource constraints.
- **S6 — Apple, BGContinuedProcessingTask:** https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask — iOS 26 availability and abrupt termination handling.
- **S7 — Apple, Foreground instance masks:** https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest — candidate API located through official documentation search; detailed model/device suitability remains to be evaluated, not verified here.
- **S8 — Apple, RAW and ProRAW:** https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats — capability detection, DNG plus processed output and capture constraints.
- **S9 — Replit, Mobile apps:** https://docs.replit.com/build/mobile-app and https://docs.replit.com/build/mobile-preview-testing — official documentation search consulted for supported Expo workflow boundaries. Custom native-client integration must be independently confirmed; do not equate guided publishing with native engine validation.

Specific speech model APIs, cloud vendors, platform upload limits and storefront pricing/policies have not been exhaustively researched in this milestone. They are explicit implementation/release gates, not implied capabilities.
