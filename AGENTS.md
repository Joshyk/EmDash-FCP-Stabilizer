# AGENTS.md

## Communication

Always reply to the user in Japanese unless the user explicitly asks for another language.

Mac の UI 操作が必要な場合、ユーザーが操作可能なら Codex は先にユーザーへ
操作を依頼する。依頼時は、操作してほしい内容と実行してほしい具体的な手順を
明示し、操作後の結果を選択肢で返せる形にする。Codex が直接 Computer Use で
操作するのは、ユーザーが明示的に依頼した場合、またはユーザーが操作できず
UI 操作が必要な場合に限る。
Final Cut Pro の quit/open は、Computer Use より先に Terminal/SSH から
`osascript` や `open -a "Final Cut Pro"` で実行する。Computer Use は、ユーザーが
明示的に許可した quit/open 操作、または Terminal/SSH でできない UI 操作だけに使う。
Final Cut Pro の E2E UI 操作は、座標クリックより AppleScript menu item、keyboard
shortcut、AX direct access を優先する。UI 操作スクリプトが失敗した場合は、同じ
失敗を再試行でごまかさず、subagent に該当スクリプトを読ませて primary path を
AppleScript/shortcut 化できるか確認・修正させる。どうしても座標クリックが必要な
場合だけ、最後の fallback として使い、その理由と fallback 使用をログへ明示する。
ユーザーの FCP 操作や確認待ちで作業を止める場合は、チャットだけでなく
Codex Stop hook と同じ iMessage 経路で通知する。送信先と送信方法は
`/Users/justadev/.codex/hooks/imessage_stop.py` の設定を source of truth にし、
`CODEX_HOOK_IMESSAGE_TO` が未設定なら hook の default recipient を使う。
macOS `display notification` だけではユーザーが気づかないので、待機・操作依頼の
主通知として使わない。

## Project

This repository hosts `Tokyo Walking Stabilizer` and its local support tools. The
FxPlug target itself must stay native FxPlug/Metal code for Final Cut Pro and Motion,
but the repository may also contain the external Stabilizer Event Analyzer web UI,
FCPXMLD parsing/import builders, and native analysis helper code used to generate
Event-scoped persisted analysis caches.

Keep the boundary explicit:
- Do not put web frontend files, Node servers, Python scripts, standalone helper
  binaries, or FCPXMLD import builders inside the FxPlug bundle, Motion Template,
  or `fxplug/TokyoWalkingStabilizer/Plugin/` runtime path.
- Do keep external analyzer code in a clearly named local support-tool directory
  such as `Stabilizer-Event-Analyzer/`, `event_analyzer/`, `node_web/`, `scripts/`,
  or `native_analyzer/` when that is the implementation being worked on.
- Do not reintroduce CommandPost/legacy timeline automation or hidden shared-cache
  fallback workflows unless the user explicitly asks for that separate integration.
- Event Analyzer output must still write to an explicit Event cache root selected by
  the user or resolved from the selected Event; it must not silently write to a
  shared Application Support fallback.

The effect intentionally avoids Final Cut Pro's built-in `Stabilization`, because that
effect applies its own internal crop/scale. The native effect renders a transformed source
texture with Metal and applies automatic walking-gimbal stabilization inside the FxPlug
render path.

The primary footage this stabilizer is designed to correct is walking footage captured with
a camera mounted on a gimbal. The gimbal reduces gross camera shake, but the operator's body
motion still introduces walking-induced movement, including micro impulses, vertical bob,
residual pitch/yaw/roll, macro jitter, and parallax between near ground and distant
background. Stabilization design and tests should treat those body-motion artifacts as the
core problem, not as generic tripod shake or purely optical crop drift.

The `1.1.1` far-field micro-shake implementation with schema 45 is the current
baseline. Preserve schema 45's fps-derived dominant `5x9` far-field mesh window
evidence for short source-space lens/camera shake up to one second. Future
changes should not return to fixed-frame shake windows, hidden fallback
smoothing, or visible local mesh warps that make mountains, clouds, ridgelines,
or horizons pulse. Earlier schemas are intentionally unsupported and require a
fresh Event Analyzer run.
For 1px-class far-field shake detection, prefer source-resolution FCP export
analysis over FCP Viewer screen pixels. Viewer screen-capture E2E is still required
for playback cadence, plugin startup, proxy/Green-channel evidence, and visible
acceptance, but it is not the precision measurement surface for subpixel or
single-pixel ridge/cloud/horizon residuals.

## Analysis Cache And Legacy Host Analysis

Current analysis generation is owned by the local Stabilizer Event Analyzer. New FxPlug
effect instances are cache consumers: they validate Event-scoped persisted analysis, render
from the prepared motion path, and do not expose `Sample Size`, `Start Host Analysis`,
`Clear Host Analysis Cache`, or `Queue` in the visible Inspector. If an older saved timeline
instance still shows hidden Host Analysis controls, those controls are legacy
compatibility/debug paths and must not become the primary workflow again.

The legacy FxPlug Host Analysis path uses Final Cut Pro's FxPlug `Host Analysis`
infrastructure to request GPU analysis frames from the host. Any native analysis path must
use Metal compute for luma downsampling and frame-to-frame motion search. Do not add a CPU
analysis fallback; if Metal analysis resources are unavailable, fail the analysis path
visibly in logs/status.

Completed analysis frame sets should be persisted inside the active Final Cut Pro
library bundle, scoped to the current Event resolved from `FxProjectAPI.mediaFolderURL()`
when the host-provided folder is inside an Event. If the host-provided folder is a library
temp folder instead of an Event folder, the runtime may use an unambiguous top-level Event
resolver, such as the single Event that already has Final Cut Pro `Analysis Files`; it should
start access to the host-provided media folder before inspecting the library bundle and verify
the selected Event by creating the `TokyoWalkingStabilizerHostAnalysis` cache root. If
`mediaFolderURL()` reports `kFxError_NoMediaFolder` for a Final Cut Pro library saved without
Collect Media, the runtime may resolve the active Final Cut Pro `.fcpbundle` from
FCP's `FFActiveLibraries` bookmark list and then run the same Event resolver. Final Cut Pro's
active-library bookmark may be security-scoped or regular, so try security-scoped resolution
first, log when regular resolution is used, and start security-scoped access when the resolved
URL grants it. If multiple libraries are active, the resolver should first use the active
Host Analysis range and existing Final Cut Pro `Analysis Files/Stabilization` range names to
select one Event across active libraries. If no range match exists, it may use Final Cut Pro's
`FFSidebarModuleLibrary` media sidebar selection only when the selection UUIDs match exactly
one active library and the selected Event UUID resolves through `CurrentVersion.flexolibrary`
metadata to an existing top-level Event folder; do not use stale import-target UUIDs. Otherwise multiple active
libraries, unreadable active-library state, or an unwritable selected Event cache root must
fail visibly as `Project Bundle Cache Unavailable - Ambiguous Active Libraries` instead of
falling back to a shared location. When multiple
Events have `Analysis Files`, the resolver should use the active Host Analysis range and
existing Final Cut Pro `Analysis Files/Stabilization` range names to choose a single Event.
Ambiguous Event candidates must fail visibly as `Project Bundle Cache Unavailable -
Ambiguous Event` instead of writing to the wrong Event. Store the cache under the
Event's `Analysis Files/TokyoWalkingStabilizerHostAnalysis/` directory so analysis files are unique
to that Event and do not appear as top-level library content. The runtime
may move older top-level `TokyoWalkingStabilizerHostAnalysis/`, media-folder-local
`TokyoWalkingStabilizerHostAnalysis/`, or `__.fcpdata.apple.com/TokyoWalkingStabilizerHostAnalysis/`
caches into the Event `Analysis Files` cache root, but it must not silently fall back to an
out-of-bundle or library-wide shared cache. The Event cache contains
`host-analysis-v2.json`, `host-analysis-index-v2.json`, `host-analysis-render-offset-v2.json`,
and range-indexed files under `caches/`. Range-indexed cache filenames and index entries
should include a readable clip label when available, analyzed start/end, actual sample size,
frame count, and representative fingerprints; correctness still depends on saved
fingerprints and source-frame validation, not the label. If the runtime cannot resolve a writable Event cache
root, surface `Project Bundle Cache Unavailable` instead of falling back to a shared
Application Support cache or a library-wide cache. During Final Cut Pro Host Analysis, it
may complete the current analyzer session in memory and surface `Ready Memory Only - Project
Bundle Cache Unavailable`; that completed in-memory analysis may drive the current
viewer/render session, but it must not persist to a shared or out-of-bundle cache and the
status must make the missing Event cache visible. If an Event cache root becomes available
later, the completed in-memory analysis should be persisted to that Event cache and the
Inspector should move to ordinary `Ready (...)` status instead of leaving `Ready Memory Only`
behind. Resolver decisions must log the host `mediaFolderURL`, `documentID`, active-library
bookmark candidates when used, bundle root, Event candidates, selected Event, and rejection
reason with public `os_log` fields. Cache candidates must be validated
against the current source frame before reuse. Rejected candidates should be visible in
logs/status and should not be deleted just because they do not match the current clip.
If `Ready Memory Only - Project Bundle Cache Unavailable` recurs while logs show
`FxProjectAPI unavailable`, `Active library resolver read 3 active library bookmark(s)`,
and `Ambiguous active Final Cut libraries`, check Final Cut Pro's `FFActiveLibraries` and
`FFSidebarModuleLibrary` state before changing cache code. A known recurrence is FCP keeping
multiple regular/stale active-library bookmarks, such as `test-gh6.fcpbundle`,
`template.fcpbundle`, and an external editing library, while the sidebar selection contains
an Event UUID that does not resolve through `CurrentVersion.flexolibrary`. That is an
environment/active-library ambiguity, not a missing entitlement or a reason to add a shared
cache fallback. Close the extra libraries or make FCP expose a single unambiguous active
library/Event, then rerun the Event Analyzer and verify the Event-scoped
`Analysis Files/TokyoWalkingStabilizerHostAnalysis/` cache appears.
The current compatibility `Start Host Analysis` button, when present on older timeline
instances, should only reload and use a saved persistent Event Analyzer cache. It must not
ask Final Cut Pro to start a new Host Analysis pass. If the loaded cache is rejected for the
current clip, the next start should skip that rejected cache and keep `External Analysis
Required - Run Event Analyzer` visible. `Clear Host Analysis Cache`, when present on older
instances, must not delete Event Analyzer cache files and should show that the external cache
is managed by the Event Analyzer.
Keep the plug-in target signed with sandbox and security-scoped file entitlements so the
Host Analysis runtime can open the `FxProjectAPI.mediaFolderURL()` security-scoped URL. The
target may also carry a read-only home-relative exception for Final Cut Pro's preference
plist so the no-media-folder resolver can read `FFActiveLibraries`; this exception must not
be used to add a shared or out-of-bundle cache path. The debug-signed local build may carry
read-write exceptions for shared `test_fcp_project/stab-test.fcpbundle` and
`test_fcp_project/test-gh6.fcpbundle` fixtures so Codex-driven FCP tests can persist
Event-scoped caches when Final Cut Pro's active-library bookmark is not security-scoped. It
may also carry a local read-write exception for the user's external Final
Cut Pro editing volume when Final Cut Pro stores active-library bookmarks as regular
bookmarks; this is only to let the sandboxed FxPlug inspect and write Event-scoped cache
roots inside the active `.fcpbundle`, not to add shared or out-of-bundle cache paths.
Keep in-progress Host Analysis session state process-wide because Final Cut Pro may call
setup, frame analysis, and cleanup through different FxPlug instances in the same plug-in
process. That process-wide state must isolate per-clip in-progress stores; ambiguous
callbacks should fail visibly instead of appending frames to an arbitrary active clip. Do
not collapse completed cache buckets across clips or sample sizes.
If Final Cut Pro restores or reports an in-progress Host Analysis while a compatible saved
cache is already present, the render/cache consumer should still reload and prefer the saved
cache; transient analyzer callback status must not mask the shared ready cache in the
Inspector. When analyzer callback status is the only active state, `Host Analysis Status`,
`Sample Info`, and `Queue` should all be published from that same in-progress analysis
store; do not combine `Analyzing Host Frames (N)` with stale shared-cache metadata from a
previous clip. `Sample Info` should combine the accepted sample percentage with the actual
analysis pixel sample and frame count. `Clip Range` is deprecated from visible Inspector
metadata. Stale `Cache Unsupported` or `Cache Incomplete`
status must not stop later
preview/render consumers from noticing a changed persistent cache signature and loading a
new compatible saved cache.
Persistent cache compatibility is based on cache schema, exact analyzed source range, sample
size, frame fingerprints, and current source-frame validation, not the visible FxPlug runtime
version. Render-only version bumps should reuse saved Host Analysis cache candidates from the
active `.fcpbundle`. When a motion-path algorithm change needs a new write schema, keep
backward read compatibility for still-valid recent schemas by listing them in
`supportedCacheSchemaVersions` and the feedback CLI's supported schema list; do not reject old
caches solely because a newer schema is now written. Unsupported schema candidates should
surface `Cache Unsupported - Run Event Analyzer` in the Inspector, remain on disk, and require
an explicit new Event Analyzer run instead of being silently ignored or deleted. Supported-schema
caches with incomplete prepared path arrays or incomplete frame coverage for the saved
analysis range should surface `Cache Incomplete - Run Event Analyzer`, remain on disk, and
require a new Event Analyzer run.

The local Event Analyzer should read user-controlled sample size once when analysis starts.
New FxPlug effect instances must not publish a visible `Sample Size` control. The default
should be `100%` so analysis uses full source detail unless the user explicitly selects a
smaller debug sample, while still offering `75%`, `50%`, `25%`, and `10%` options. The
sample image must always be derived from the original clip dimensions using the selected
percentage option. Long clips should keep that requested percentage. In-progress analysis
should stream frame-to-frame motion in memory and keep only the previous luma buffer needed
for the next Metal motion search; do not write per-frame `.luma` scratch files.
Persistent cache files should store prepared paths, frame timing, blur values, and
fingerprints instead of every frame's full luma sample.
Cache candidates should be sample-size-scoped. Do not collapse different `Sample Size`
outputs into one in-progress builder or one retained cache bucket; the cache index should
retain candidates independently per actual `sampleWidth`/`sampleHeight`.
Cache persistence should treat the prepared analysis frame set as authoritative. The
retained source-frame map may be reduced after Metal preparation and must not prevent a
completed prepared path from being saved.
The feedback CLI under `fxplug/TokyoWalkingStabilizer/scripts/` reads saved Host Analysis cache
files for diagnostics only. It must not become a second stabilization runtime or silently
repair malformed cache data; mismatched frame/path arrays should fail visibly and require a
new Event Analyzer run. Its cache inventory mode should list saved cache readiness without
repairing, deleting, or promoting cache files. Feedback band estimates should mirror the
render path's order:
measure Micro Jitter against the outer-frame baseline first, then compute Macro Jitter
and Turn diagnostics from the micro-cleaned path.
The feedback report should print bands in Debug Overlay/render order (`MIJIT`, `MAJIT`,
`WARP`, `TURN`) and choose the top remaining band separately. Its `--turn-window` option should
match the Inspector `Turn Detection Window` when that UI value is not the default `6.0`.
Fine jitter analysis should use Metal block matching across multiple source-frame regions,
reject outlier blocks, and expose low block-confidence states in status/debug output instead
of silently falling back to a coarse global shift. Walking landscape analysis should
prioritize upper-frame far-field blocks so distant mountains/background motion is not
dominated by close grass, water, or road parallax. Dense block-grid changes that alter
prepared analysis output must bump the Host Analysis write schema and synchronize the Event
Analyzer writer, FxPlug supported schemas, feedback CLI supported schemas, and docs together.
Motion-path algorithm changes that alter prepared analysis output should bump the Host
Analysis write schema, but keep previous still-valid schemas in the explicit supported-schema
list unless the stored fields are no longer safe to interpret.

## Diagnostics

Debug/status diagnostics should expose tracking confidence, blur/sharpness, residual error,
raw Micro Jitter impulse, and search-radius edge-hit counts so fine-shake causes are
visible while tuning walking footage. Debug Overlay must keep the shared 21-row contract:
`X OFFSET`, `Y OFFSET`, `ROLL`, `CROP`, `TURN`, `MACRO JITTER`, `MICRO JITTER`, `FAR WARP`,
`LENS`, `SMOOTHING`, `TRACKING`, `WALKING`, `SHARPNESS`, `RESIDUAL`, `SEARCH HEADROOM`,
`TURN CONFIDENCE`, `MACRO CONFIDENCE`, `MICRO CONFIDENCE`, `WARP CONFIDENCE`,
`LENS CONFIDENCE`, then the runtime/source row. Activity rows must report final values actually
applied to Metal. `TRACKING`, `WALKING`, `SHARPNESS`, `RESIDUAL`, and `SEARCH HEADROOM` should all be quality bars where
higher means better tracking evidence and lower means weaker evidence. All quality and
confidence rows must stay grouped immediately above the version row. Debug Overlay should also expose a compact
active runtime/source row so stale saved Inspector strings do not hide which binary is rendering:
`ORIGINAL <version>` means an original/optimized render frame is using that FxPlug runtime version, while
`PROXY <version>` means a proxy render frame is using the same saved Host Analysis path.
The overlay panel should scale proportionally to the current render output so Final Cut Pro
original/proxy playback presents one readable viewer footprint; high-resolution original
frames must not make the bars tiny, and proxy output must not make them balloon over the
preview.
Debug Overlay active bars should use one neutral white color so the overlay remains readable
in Viewer `Green` channel and does not encode state through changing colors. The row labels
and fill lengths carry the diagnostic meaning.

When verifying a Final Cut Pro-visible playback problem, especially zoom pulsing, wobble,
crop breathing, turn smoothness, or proxy playback heaviness, do not rely only on still
screenshots or Inspector/log state. Capture a short screen-recorded video of the Final Cut
Pro Viewer around the reported time range, using the same project, clip, proxy/original
setting, and effect controls the user reported. Inspect the recording visually and, when the
problem is motion/scale related, analyze the captured frames with `ffmpeg`/OpenCV or an
equivalent local tool to measure frame-to-frame apparent scale/translation changes. Treat
that video evidence as part of the verification result before claiming the visible issue is
fixed.
Do not downsample or thin verification frames when the reported artifact is a single-frame
or frame-local jump. Respect the source clip cadence, including 50fps, `60000/1001`
(`59.94fps`), and other high-frame-rate clips, and evaluate screen captures, OpenCV motion
metrics, and cache path diagnostics at frame cadence close to the source/captured cadence
instead of reducing the analysis to about 30fps; otherwise x/y frame jumps can be missed. If
the screen recording cannot preserve the source cadence exactly, still sample every captured
frame and make the capture frame rate limitation explicit in the result.
Do not use a small fixed screenshot set, such as 12 frames, as the basis for accepting
motion-quality fixes. For screen-capture diagnostics, treat every captured frame, the
per-frame CSV metrics, and the full diagnostic overlay video as the primary evidence.
Contact sheets are only navigation aids for locating suspect frames.
The Stabilizer evaluation policy is video-first, not screenshot-first. Screenshots,
contact sheets, Inspector state, and logs can guide investigation, but they cannot decide
acceptance for smoothness. Acceptance must come from a Final Cut Pro Preview screen-capture
video, full per-frame CSV/PTS diagnostics, and an explicit visual review of the recorded
motion. Record at least 3-5 seconds for a local spot check and roughly 20 seconds for a
known regression or important motion section. The purpose of the E2E harness is to make
the real FCP Preview smooth, not merely to satisfy numeric thresholds; if the recorded
video still shows clouds, ridgelines, horizon lines, zoom, crop edges, or cadence artifacts
moving unnaturally, treat the result as failed even when metrics report pass.
Stabilizer smoothness acceptance must be video-first. Do not accept a change based on a
few screenshots, a still contact sheet, Inspector text, or numeric pass/fail alone. Record
the Final Cut Pro Viewer with the target project, target timecode range, `Proxy Only`,
Viewer `Green` channel, and the Stabilizer `Debug Overlay` visibly enabled,
then judge the result from the video, the full per-frame CSV, PTS/frame-interval evidence,
and a visual review of the actual motion. Keep `Remove Black Edges` off for ordinary
smoothness, turn, ridge, horizon, and proxy-playback review so exposed edges remain a useful
diagnostic and auto-crop zoom does not hide motion defects. Turn it on only for the dedicated
Remove Black Edges / Auto Crop / black-edge breathing regression pass. The evaluator must
measure frame-to-frame translation jump, scale pulse, ridge/horizon residual, black-edge
breathing, near-duplicate/freeze frames, and PTS irregularity across every captured frame.
If the metrics pass but clouds, distant ridgelines, or the horizon still visibly shimmer,
pulse, or step in the recorded FCP Preview, treat the result as failed and keep iterating.
The evaluator must keep visual review explicit: default to `--visual-review not-reviewed`
and treat that as an acceptance failure for these cases. Only rerun or mark evaluation with
`--visual-review passed` after actually watching the recorded FCP Preview video and checking
the full per-frame CSV/PTS diagnostics; use `--visual-review failed` when the video still
shows visible shake, crop breathing, freeze, or cadence artifacts.
For development changes that affect stabilization smoothness, Auto Crop / Remove Black
Edges, turn smoothing, playback zoom, or proxy playback behavior, run the repo E2E
screen-capture case for `P1000307.mov` before claiming the issue is fixed. The canonical
case is `tests/stabilizer_e2e_cases/p1000307_turn_1m26_1m46.json`: open
`/Users/justadev/Developer/EDT/Command-Post-Em_Dash/test_fcp_project/stabilizer_super_smoother.fcpbundle`, use the
`P1000307 Stabilized Review` project, play the `00:01:26` to `00:01:46` turn section in
proxy with the Stabilizer effect and `Remove Black Edges` off for the baseline recording,
then evaluate the recording with `scripts/stabilizer_fcp_screen_capture_e2e.sh`.
This is a fixed roughly 20-second regression window; do not replace it with a few still
frames or a shorter contact-sheet-only inspection.
The second fixed regression is `P1000304` around `00:04:28`, focused on the mountain
ridgeline, clouds, and horizon. The canonical case is
`tests/stabilizer_e2e_cases/p1000304_ridge_4m23_4m43.json`. Record enough context around
that point, typically at least 3-5 seconds for a spot check and roughly 20 seconds for the
canonical regression window, with the same `Proxy Only` and default `Remove Black Edges` off
requirements.
Near-ground grass, road, or water may move more than the far field, but distant background
instability is a visible-quality failure.
Every stabilization implementation iteration must also run a dedicated `Remove Black Edges`
on regression pass before claiming the issue is fixed. Use the same fixed projects,
timecode ranges, `Proxy Only`, Viewer `Green` channel, and visible Stabilizer
`Debug Overlay`, but enable `Remove Black Edges` only for this crop/black-edge test.
Treat zoom pulse, crop breathing, black-edge breathing,
or playback heaviness in that crop-on pass as blocking even if the ordinary crop-off
baseline looks smooth.
When an E2E case specifies proxy playback, such as `playbackMode: "Proxy Only"`,
the test setup must actively set Final Cut Pro's Viewer media playback to that proxy mode
before recording. Use `Proxy Only`; `Proxy Preferred` is not valid for these E2E cases
because Final Cut Pro can silently fall back to original/optimized media. Confirm the
effective render source through FxPlug runtime evidence, such as the Debug Overlay `PROXY <version>`
row or Host Analysis logs reporting `proxy yes`; a capture that logs `proxy no` or
otherwise cannot prove proxy playback is not valid evidence for that case and must be rerun
after fixing the setup.
For Stabilizer playback and FCP Preview E2E capture, set Final Cut Pro's Viewer channel to
`Green` (`View > Channels > Green`) before playback/recording. Green-channel playback has
shown better performance for this workflow and should be the default verification channel
unless the task is explicitly checking full-color output, color handling, or channel-specific
render correctness.
If Final Cut Pro opens a proxy E2E case with a black/uninitialized Viewer, the harness may
warm the Viewer by temporarily selecting `Optimized/Original`, but it must immediately
restore `Proxy Only`, log that warmup explicitly, and record/evaluate only after Proxy Only
is active again. This warmup is not a substitute for Proxy Only playback evidence.
If the screen-capture evaluator reports zoom pulse, visible black-edge breathing, or
insufficient tracking confidence, treat that as a blocking regression and keep iterating.

## Playback And Render

Analysis playback must render from prepared motion paths for the active FxPlug runtime.
For current new effect instances, those paths come from the local Event Analyzer cache and
render/preview callbacks must not auto-start analysis. The legacy hidden `Start Host
Analysis` path is the only path that may call `startForwardAnalysis` when that legacy path is
intentionally exercised. If Final Cut Pro reports that another
Host Analysis is already requested or running, queue the requested effect instance for
serial analysis and surface `Queued Host Analysis` in the Inspector instead of failing
silently. Also queue the request when this plug-in process already has an active or
reserved Host Analysis session for another clip, because Final Cut Pro may otherwise run
multiple Stabilizer Host Analysis jobs at the same time. Queue drain should run as
retryable one-shot passes after analysis callbacks complete; when the active clip finishes,
the next queued request should be the only request handed to `startForwardAnalysis`.
If `Start Host Analysis` is pressed repeatedly while the same effect instance is already
queued, replace that instance's older queued request and keep its most recent button press
without discarding queued requests for other effect instances.
In-progress Host Analysis state must be per clip/session so requested clips, including clips
with different actual sample sizes, never share a streaming builder. The
active runtime uses a process-wide shared Host Analysis render/cache store after completion
because Final Cut Pro may call analyzer and preview/render through different FxPlug
instances. Persistent cache files are the cross-process reuse path after source-frame
validation. Completed analysis should be written to the active `.fcpbundle` project cache
directory, not to a shared user Application Support cache or only to the current extension
container. When an analyzer instance saves a completed cache,
render/preview instances and plug-in state callbacks should notice cache file changes, reload
persistent cache candidates on demand, and update the hidden render revision with a
process-independent small numeric token even when they already hold an older prepared
analysis; this keeps the stabilized preview visible after serial queued analysis and when
analyzer and render use different FxPlug processes. Do not use per-process revision
counters as the hidden render invalidation value because analyzer and render processes can
generate the same counter value for different completed clips. Do not repeatedly set the
hidden render revision when Final Cut Pro already holds the same value, because that can keep
the effect in a loading/invalidation loop. Render/preview instances should also monitor the
shared persistent cache location and publish the hidden render revision when a compatible
completed cache appears, because analyzer callbacks may complete in a different FxPlug
instance or process than the stale viewer preview. A failed hidden parameter update should
not be recorded as published; a later valid callback or monitor tick should retry.
Analyzer completion and persistent-cache monitor ticks should dispatch the status/info/render
revision publication onto the FxPlug main queue before calling `FxParameterSettingAPI`, so
Final Cut Pro treats the hidden revision as a real preview invalidation.
Fingerprint mismatches must reject a
candidate instead of accepting a different clip by time proximity alone. If Final Cut Pro keeps
reporting a busy state when the serial queue tries to drain, keep the latest request queued
visibly and retry later. A queued start request must remain a pending request for that effect
instance; do not let a completed shared render/cache store from another clip satisfy or
skip the queued clip's own Host Analysis start. Because Final Cut Pro can call analysis
setup/analyze/cleanup on a different FxPlug instance than the Inspector button instance,
analysis completion/failure should clear process-wide analysis bookkeeping before queue
drain. A queued request should retain the `FxAnalysisAPI` obtained when Start was pressed;
retry callbacks must not drop the queued request just because `FxAnalysisAPI` cannot be
reacquired from a later callback context. Do not use plug-in-local active markers as the authority for blocking another
Inspector `Start Host Analysis` action; the start path should ask Final Cut Pro's
`analysisStateForEffect()` and queue only when the host reports a busy/requested state.
When analysis completes memory-only because the Event cache root is unavailable, keep
completed in-process analyses isolated by analyzed timeline range plus sample/fingerprint
identity so serial analysis of a later clip does not discard the earlier clip's usable
viewer result or collide with another clip that has the same source-time range.
Do not re-run full block matching across
the analyzed frame set on every render frame. Keep `Host Analysis
Status` visible in the Inspector, update it to `Ready (... frames)` after completed
analysis, update `Analyzing Host Frames (N)` during real frame analysis, and include the
active FxPlug version there when Final Cut Pro accepts status parameter updates. Debug
Overlay should remain the live render-runtime indicator because
older saved Inspector strings can remain stale on existing timeline instances.
Render playback must tolerate trimmed clips whose render time differs from Host
Analysis frame time by matching the current render frame fingerprint back to the analyzed
frame set and applying that time offset before sampling the prepared motion paths. If Final
Cut Pro reports a render/timeline range that differs from the saved source analysis range,
render may accept the active cache only after the current source-frame fingerprint validates
against the saved frame set. Once an
analysis is validated, render playback should keep using the prepared motion path even when
Final Cut Pro is playing proxy media; proxy media is rejected only for Host Analysis input
and for validating an unvalidated persisted cache. If a saved Host Analysis cache is loaded
while Final Cut Pro is currently playing proxy media, render playback should still use the
loaded cache immediately rather than requiring re-analysis, keep the preview invalidation
revision moving so the stabilized proxy preview appears, and let original-media validation
happen later when original frames are available. If Final Cut Pro cannot provide the render
source frame, such as when Viewer playback is set to missing proxy media, render should
surface `Source Media Unavailable - Check FCP Proxy`, leave the saved Host Analysis cache
intact, and avoid drawing Debug Overlay diagnostics over the placeholder frame. When render
uses a saved analysis while the current source is proxy-scaled, status should make that
visible as `Original Analysis - Proxy Preview` instead of silently promoting the cache to
ordinary `Ready`. If the current frame lacks pixel-transform metadata but is not known to be
scaled/proxy media, status should make deferred validation visible as `Original Analysis - Preview Unvalidated` instead of labeling the preview as proxy.
Render-time transitions between original/optimized and proxy preview should publish
`Host Analysis Status`, `Sample Info`, `Queue`, and the hidden render revision when the
shared store revision changes, even if the render callback already holds a locally matching
hidden revision value.
When original-media validation maps a trimmed timeline render time back to the analyzed
source time, render instances should persist that offset with the Host Analysis cache
identity so proxy-only render instances and processes can sample the same prepared motion
path instead of falling back to an unmapped timeline time.
Proxy/scaled media detection should treat pixel transforms that deviate from original
`1.0x/1.0x` in either direction as scaled media: Host Analysis must reject those frames,
while render playback with a saved analysis should keep using the prepared original-media
motion path instead of validating fingerprints against the scaled proxy frame. If Final Cut
Pro reports a render/timeline range that differs from the saved source analysis range during
scaled/proxy playback, the runtime may use that range-mismatched active cache for preview only
when the cache start matches the current clip and the current render time is inside the saved
analysis range; otherwise it must keep the missing validation visible instead of silently
accepting the cache.
When the
effective overall transform strength is zero, rendering must
bypass prepared motion-path sampling and output an identity transform with no debug overlay.
Render-time frame/window lookup should use the sorted prepared frame times directly instead
of repeatedly scanning the full analysis frame set on every preview sample.
When Host Analysis/cache state changes, update a hidden render-affecting revision parameter
so Final Cut Pro invalidates the preview/render cache and the viewer reflects the prepared
stabilization immediately. If Final Cut Pro reports a stale hidden revision value after an
attempted publish, keep retrying the same revision instead of treating a plug-in-local
publish record as proof that the host accepted it.
Render playback should favor the smoothest visible pan over low per-frame compute cost:
after calculating the prepared-path transform, sample neighboring render times symmetrically
and blend the final automatic transform with zero phase so the preview does not step between
corrections. Near clip edges, average only in-range neighboring samples instead of clamping
out-of-range samples to the first or last analysis frame, so end frames are not over-weighted.
This render-time smoothing must not require rerunning Host Analysis or changing the cache
schema.
Render-time smoothing must not average away Micro Jitter impulses or roll jitter needed
to stabilize fine distant ridge-line shake. Smooth Turn Smoothing and Macro Jitter
components independently, then recombine them with the current render frame's Micro
Jitter X/Y/roll correction. Micro Jitter debug/status output should show the raw confidence
and effective correction strength so low-confidence gating is visible. Far-field Warp should
not use the full broad transform-smoothing window; keep it on a short in-range render-time
smoothing window so ridge-line correction stays responsive while single-frame gate flicker is
still damped.
Auto Crop timing controls define the render-time zoom envelope around strong internal
Auto Crop keypoints, including turn-driven crop demand. `Auto Crop Zoom-In Time` is the
lead-in before the keypoint peak: a value of `10.0` means Auto Crop may begin zooming in up
to 10 seconds before the peak. `Auto Crop Hold Time` is the maximum time to hold the peak
scale after that peak: a value of `2.0` means hold the maximum zoom for up to 2 seconds.
`Auto Crop Zoom-Out Time` is the release after the hold: a value of `10.0` means return
toward `1.0x` over up to 10 seconds. Therefore the default `10.0 / 2.0 / 10.0` contract is
start zoom-in 10 seconds before the crop/turn peak, hold maximum zoom for 2 seconds, then
zoom back out toward `1.0x` over 10 seconds. Clip edges, overlapping keypoints, black-edge
coverage repair, rate limiting, and smoothing may keep scale above `1.0x` longer or raise it
slightly when needed to avoid visible black edges, but the parameter semantics must not be
reversed or silently redefined.

## Walking Correction Stages

Fine high-frequency shake should be handled by render-time Micro Jitter strength controls
that compare X/Y/rotation against an outer-frame linear prediction using seconds-based
windows: skip the center `0.10` second shock region and predict from outer samples up to
`1.0` second away. Micro Jitter should suppress micro landing shock as a frame-level
impulse rather than treating it as periodic smoothing, and it should not require rerunning
Host Analysis. Do not add or expose a user-facing Micro Jitter window; fine jitter should
be corrected from the current render frame's impulse against the fixed seconds-based
outer-frame baseline using the multi-block Host Analysis path. Micro Jitter confidence
should be evaluated per render frame from current tracking quality, accepted block coverage,
blur, local baseline support, surrounding micro noise, and whether the center frame
departs from its outer-frame baseline; do not force a hidden minimum confidence floor.
Medium-confidence response may be curved upward for a more useful debug pass. Micro
Jitter and Macro Jitter may use a more assertive medium-confidence response
than Turn Smoothing and Far-field Warp, but zero confidence must still produce zero
correction. Moderate landing impulses should not be buried by an overly high
surrounding-noise threshold.
The surrounding-noise floor should be capped below the full impulse response point so repeated
walking motion does not hide a real center-frame landing impulse.
Micro Jitter strength values should be direct removal amounts with exposed X/Y maximums
of `10.0`, X/Y defaults of `4.0`, and an exposed Rotation maximum/default of `4.0`/`1.0`. Values above `1.0` may compensate when
frame-local confidence makes correction too weak, but applied correction must clamp at full
detected-impulse removal during render so high slider values do not add inverse shake.
Micro Jitter Rotation Strength should default to `1.0`.
Medium-period walking shake that is longer than Micro Jitter should be handled by the
render-time `Macro Jitter` stage. Keep its time window fixed
inside the implementation at `2.0` seconds, expose only X/Y/Rotation strength controls with
X/Y maximums of `10.0`, X/Y defaults of `4.0`, and a Rotation maximum/default of `4.0`/`1.0`, do not add a user-facing Macro Jitter
Wobble window, compute it from the micro-cleaned baseline, and feed Turn Smoothing from
the macro-jitter-smoothed path so the same band is not removed twice. Macro Jitter residual gating
should use robust window evidence instead of the single worst frame in the window, so one
bad block-match frame does not suppress the whole medium band. Medium MAJIT bands may reach
full confidence sooner than the broad UI scale, and the default Y strength should remain high
enough to remove step follow-through. Macro Jitter
Rotation Strength should default to `1.0`.
Micro Jitter and Macro Jitter may use a count-aware walking-band tracking
gate that eases block coverage only when enough motion blocks were accepted. Far-field Warp
and Turn Smoothing should keep the stricter tracking gate so weak evidence does not create
swimming warp or false turn smoothing.
The render path must not compute Macro Jitter from the raw or jerk-limited broad path,
because that reintroduces Micro Jitter shock into the medium-period band.
Prepared Host Analysis motion paths should be post-processed with a zero-phase jerk limiter
before caching. The limiter should clamp isolated acceleration spikes in X/Y/roll while
preserving path endpoints so total analyzed turn amount is not lost and real panning is not
delayed into a sliding path. Keep separate raw X/Y/roll impulse paths for Micro Jitter so
the jerk limiter does not erase frame-level shake before render-time micro correction.
Because this changes prepared path semantics, bump the Host Analysis cache schema when it
changes, while preserving backward read compatibility for still-valid older schema entries.
Large segmented walking turns should be controlled by the render-time `Turn Smoothing
Strength` slider, where higher values concatenate stop-and-go X-axis pan motion into a
smoother monotonic S-curve turn intent instead of a straight-line fit. The default is `12.0`,
the exposed maximum is `36.0`;
values above `1.0` may compensate for low-confidence gating when turn correction is too
weak, and render-time TURN must not add a separate full-removal cap or output-edge soft cap.
Turn smoothing must not apply Y or roll correction. With `Remove Black Edges` / Auto Crop
enabled, crop and edge protection should be handled by precomputed, smoothed crop and
edge-guard plans rather than by capping TURN itself, so the zoomed margin is spent on
making the turn move as a smoother, more uniform pan. Crop-on playback must spend that margin through precomputed, smoothed crop and
prepared-turn plans; it must not rely on final frame-local scale repairs that create
zoom/crop pulsing. With Auto Crop disabled, exposed black edges should remain a useful
diagnostic while the crop-off edge guard stays low-speed and separate from TURN. `Turn Detection Window` must use the Inspector UI value, and its UI
minimum must be the fixed `2.0` second Macro Jitter window so TURN cannot run shorter than
MAJIT. The turn band should be measured from the macro-jitter-smoothed path instead of the raw frame
path, and Y correction must stay Micro Jitter first and Macro Jitter second so short
landing shock is not reintroduced by turn smoothing. TURN confidence should
require both tracking evidence and a real X turn band; do not keep a hidden minimum turn
confidence on low-evidence frames.
Do not reintroduce a separate post-macro Y-only bounce stage as a render stage,
Inspector control, debug row, feedback band, or cache-derived diagnostic path.

## Far-Field Warp And Edges

`Far-field Warp Strength` should expose one bundled small-clamp control for deskew/shear,
yaw/pitch proxy, and perspective/distort trim. It is intended only for distant ridge-line
shake in walking landscape footage. Keep the default at `1.0`, expose up to `12.0`, keep the
previous `4.0` strength response unchanged, keep each unit's render clamps small, surface `warp q`, shear, yaw/pitch, and perspective in
debug/status output, and render the correction from the current frame's local deviation from
its own `0.10`/`1.0` second outer-frame linear warp baseline so accumulated long-term drift
does not become a fixed deskew. Low tracking confidence or poor search-radius headroom should
gate Far-field Warp off instead of creating wave-like image distortion. Render should use a
walking-footage tracking gate tuned for 25% Host Analysis samples plus a tiny render-time
deadband so weak warp deltas do not create swimming or wave-like distortion. Medium-confidence
warp gates may be curved upward, and the tracking gate should start early enough that moderate
25% Host Analysis evidence can still correct distant ridge-line shake while reaching full
response gradually enough to avoid high-side gate jumps. The warp gate may use short local
tracking support and short render-time smoothing to avoid single-frame gate flicker, but zero
local tracking or poor current search-radius evidence must still produce zero warp correction.
`WARP CONFIDENCE` should represent the applied warp confidence after those safety gates. Bump Host
Analysis cache schema when prepared warp path semantics change.
`Edge Display Mode` should control whether transformed source pixels outside the original
image stretch edge pixels or draw black. Do not tie black outside-source pixels to `Debug
Overlay`; debug overlay should only show diagnostics.

## Source Layout

```text
Stabilizer/
  AGENTS.md
  README.md
  docs/
  fxplug/
```

The Xcode project lives at
`fxplug/TokyoWalkingStabilizer/TokyoWalkingStabilizer.xcodeproj`. Keep FxPlug source under
`fxplug/TokyoWalkingStabilizer/Plugin`, wrapper app source under
`fxplug/TokyoWalkingStabilizer/WrapperApp`, installer scripts under
`fxplug/TokyoWalkingStabilizer/scripts`, and Motion Template resources under
`fxplug/TokyoWalkingStabilizer/MotionTemplates`.

## Test Project

Use this local Final Cut Pro library for manual end-to-end testing:

```text
/Users/justadev/Developer/EDT/Command-Post-Em_Dash/test_fcp_project/stab-test.fcpbundle
```

`stab-test.fcpbundle` is the current shared workspace test fixture outside this plugin repo.
Use it when checking the native effect against real timeline clips in Final Cut Pro.

## Shared Final Cut Pro UI Shortcut Script

The shared local AppleScript helper for Final Cut Pro UI shortcut work lives outside this
repo at:

```text
/Users/justadev/Developer/EDT/Command-Post-Em_Dash/scripts/fcp_stabilizer_shortcuts.applescript
```

For Codex-driven Final Cut Pro UI testing, prefer the repo-local wrapper first:

```sh
scripts/fcp_ui_test.sh env-check
scripts/fcp_ui_test.sh open-test-library
scripts/fcp_ui_test.sh open-project "stab test - gh6"
scripts/fcp_ui_test.sh select-playhead-clip
scripts/fcp_ui_test.sh apply-selected
scripts/fcp_ui_test.sh enable-debug
scripts/fcp_ui_test.sh dump-front-window
scripts/fcp_ui_test.sh list-caches
```

The wrapper keeps the common UI test flow terminal-first and uses the shared AppleScript
under the hood. Use free-form Computer Use only after these explicit commands fail or when a
new UI path has no helper command yet. See `docs/codex-fcp-ui-testing.md` for the expected
selected-clip workflow and cache-backed diagnostics.

From this repo, run it through the parent-relative path:

```sh
osascript ../scripts/fcp_stabilizer_shortcuts.applescript export-xml
osascript ../scripts/fcp_stabilizer_shortcuts.applescript import-xml
osascript ../scripts/fcp_stabilizer_shortcuts.applescript apply
osascript ../scripts/fcp_stabilizer_shortcuts.applescript toggle-debug-overlay
osascript ../scripts/fcp_stabilizer_shortcuts.applescript set-debug-overlay on
osascript ../scripts/fcp_stabilizer_shortcuts.applescript set-debug-overlay off
osascript ../scripts/fcp_stabilizer_shortcuts.applescript focus-inspector
osascript ../scripts/fcp_stabilizer_shortcuts.applescript open-selected-project
osascript ../scripts/fcp_stabilizer_shortcuts.applescript open-project "stab test - gh6"
osascript ../scripts/fcp_stabilizer_shortcuts.applescript select-playhead-clip
osascript ../scripts/fcp_stabilizer_shortcuts.applescript dump-front-window
```

Use it from Keyboard Maestro, Automator Quick Actions, or Terminal when manual FCP
validation needs faster access to XML export/import dialogs, `Tokyo Walking Stabilizer`,
`Debug Overlay`, selected Browser projects, or the Inspector. `Start Host Analysis` helpers
are legacy-only for older timeline instances that still expose hidden Host Analysis
controls. Grant Accessibility permission to the app that runs the script.
For project opening, prefer `open-project PROJECT_NAME` when the target Browser project
name is known, or `open-selected-project` after selecting the project thumbnail or list row
in the Browser. These commands use `Clip > Open Clip` because ordinary AppleScript click
repeats and CoreGraphics double-clicks can fail to register as a Final Cut Pro project
open in some layouts. Use
`select-playhead-clip` to reselect the timeline clip under the playhead before cache/debug
checks when Final Cut Pro focus has drifted back to the Browser or search field.
If FCP UI labels change, use `dump-front-window` to inspect the accessible roles/names and
update the shared script in the parent workspace. Do not copy a separate version into this
repo unless the user explicitly asks for repo-local divergence.

## Version Visibility

Keep `tokyoWalkingStabilizerVersion` in
`fxplug/TokyoWalkingStabilizer/Plugin/TokyoWalkingStabilizer.swift` aligned with
`CFBundleShortVersionString` in the wrapper app and plug-in plist files. User-visible
FxPlug behavior changes should also bump the plist `CFBundleVersion`, the
`ProPlugPlugInList` effect `version`, Motion Template `pluginVersion`, the version value
used by `Host Analysis Status`, and the compact Debug Overlay runtime row so Final Cut Pro
and PlugInKit do not keep stale parameter metadata.

## Verification

After FxPlug edits, run:

```sh
xcodebuild -project fxplug/TokyoWalkingStabilizer/TokyoWalkingStabilizer.xcodeproj -scheme TokyoWalkingStabilizer -configuration Debug -derivedDataPath /tmp/TokyoWalkingStabilizerDerived build
pluginkit -m -A -p FxPlug -i com.justadev.TokyoWalkingStabilizer.Plugin
codesign --verify --deep --strict /Applications/TokyoWalkingStabilizer.app
git diff --check -- AGENTS.md README.md docs/usage.md fxplug/TokyoWalkingStabilizer
```

The `TokyoWalkingStabilizer` shared scheme has a pre-build action that fails when Final Cut Pro is
running and a post-build action that runs
`fxplug/TokyoWalkingStabilizer/scripts/install_debug_app.sh`. Final Cut Pro must be quit before
building or installing; touching a loaded FxPlug bundle can leave Final Cut Pro holding a
stale PlugInKit object and produce `P1000307` helper communication errors. A successful
build should install `/Applications/TokyoWalkingStabilizer.app`, copy the Motion Template into
the user's Movies Motion Templates folder, and register its embedded pluginkit for Final
Cut Pro.
