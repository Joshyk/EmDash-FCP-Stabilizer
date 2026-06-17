# Stabilizer Event Analyzer

Local Event FCPXMLD analyzer for Tokyo Walking Stabilizer.

The workflow is:

1. Export an Event or Project from Final Cut Pro as FCPXMLD.
2. Open this local Web UI and select one or more `.fcpxmld` packages or
   `Info.fcpxml` files.
3. Choose an export from the selected file list, then select one or more Event
   media assets.
4. Use `Imports` for the generated import package and analysis staging cache.
   It defaults to the same folder as the selected export. Use `Select Imports`
   only when you want a different folder.
5. Run serial analysis for the full media duration of each selected asset. When
   multiple assets are selected, the native analyzer finishes one asset before
   starting the next.
6. Write schema-compatible Tokyo Walking Stabilizer persisted cache files to an
   explicit Imports staging folder.
7. Build an import FCPXMLD that adds Tokyo Walking Stabilizer filters carrying
   the generated cache identity.

Trimmed timeline clips are not treated as the analysis authority. The analyzer
uses Event media as the unit of work. A trimmed timeline item naturally uses the
matching portion of the full-media cache at render time.

Analysis input is original media only. When an asset has `media-rep` entries, the
tool selects only `kind="original-media"` and refuses `proxy-media` or
`optimized-media` instead of falling back to them. Assets without an original
media source are shown as unsupported in the Web UI and are not selectable for
analysis. Direct asset `src` paths that point inside Final Cut Pro `Proxy Media`
or `High Quality Media` folders are also refused.

The native analyzer prefers hardware VideoToolbox decode and requires Metal for
analysis. Compressed video samples are decoded through `VTDecompressionSession`
into Metal-compatible native YUV pixel buffers, preserving 10-bit luma for
10-bit sources. Luma sampling, blur metric reduction, cache-validation
fingerprints, and frame-to-frame block motion search run through Metal compute
kernels. If hardware decode is unavailable for a source format, the analyzer
logs the hardware failure and uses an explicit software-only VideoToolbox decode
fallback while keeping luma sampling and stabilization analysis on Metal. That
visible decode fallback is CPU work because VideoToolbox could not provide a
hardware decoder for the source. If a Metal device, command queue, or kernel
dispatch is unavailable, analysis fails visibly instead of falling back to CPU
motion search. The CPU still feeds VideoToolbox, formats Metal results, and
writes the final cache JSON. Selected assets remain strictly serial: the analyzer
finishes one asset before starting the
next. Inside that one active asset, reader lanes are used to
keep the decoder and Metal pipeline fed without user lane configuration. Each
active asset probes the Mac's active processor reader lanes, keeps the maximum
simultaneous decoder count VideoToolbox accepts for the selected decode mode,
and budgets per-lane GPU in-flight frame slots from frame size and physical
memory. Explicit lane or slot environment overrides are rejected so the run uses
the detected maximum resource plan. Reusable Metal buffers are allocated directly
instead of through a reserved `MTLHeap`, avoiding extra heap reservation on
memory-limited systems. The reported lane and slot counts show the effective
limits in use.

Some camera sources can be unsupported by Apple's hardware decoder even when
Final Cut Pro or QuickTime can play them through another path. High resolution
H.264 sources, including some Insta360 `5312x2988` originals, may be rejected by
hardware-required VideoToolbox on M1. In that case the analyzer prints the codec,
dimensions, and VideoToolbox status, then continues with the visible software
decode fallback.

When `--progress` is enabled in an interactive terminal, frame and chunk
progress updates rewrite one stderr line. When stderr is piped, such as through
the local web UI, each progress update is emitted as a `progress ...` line so
the UI can parse and display it live. Frame progress reports completed frames
and, while the first Metal command buffers are still in flight, the number of
frames submitted to the GPU.

## Run

From the repository root:

```sh
cd Stabilizer-Event-Analyzer/node_web
npm start
```

Then open `http://127.0.0.1:3091`.

`Last Analysis` reloads the exact FCPXMLD/Info.fcpxml path, selected Event media
clips, Imports folder, sample size, and debug frame limit from the most recent
analysis run. It does not open the macOS file picker and does not write any
shared fallback cache.

## Imports

`Imports` defaults to the same folder as the selected `.fcpxmld` package or
`Info.fcpxml` export. The generated `*-stabilizer.fcpxmld` import package is
written there, and analysis cache files are staged below that folder:

```text
Exports/
Exports/SomeEvent-stabilizer.fcpxmld/
Exports/Analysis Files/TokyoWalkingStabilizerHostAnalysis/
```

The tool never falls back to Application Support or any shared cache location.
