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

The native analyzer requires Metal. Luma sampling and frame-to-frame block
motion search run through Metal compute kernels, with multiple in-flight GPU
frame slots per active asset; if a Metal device, command queue, or kernel
dispatch is unavailable, analysis fails visibly instead of falling back to CPU
motion search. Selected assets remain strictly serial: the analyzer finishes
one asset before starting the next. Inside that one active asset, media reader
lanes are used to keep the GPU fed without overloading AVFoundation decode,
source texture retention, or Metal heap allocation. Each active asset defaults
to a memory-aware reader lane count derived from the Mac's active processor
count and physical memory instead of blindly using every CPU thread. 16 GB
machines default to one reader lane and two in-flight source frames so analysis
avoids swap before scaling throughput. GPU in-flight frame slots are budgeted
across the active asset's reader lanes from the Mac's active processor count
and physical memory.
`STABILIZER_ANALYZER_WORKERS` can request an explicit reader lane count, capped
at the Mac's active processor count. `STABILIZER_ANALYZER_IN_FLIGHT` can tune
the per-lane GPU frame slot count, capped by the current frame size and
available memory. The reported lane and slot counts show the effective limits
in use.

When `--progress` is enabled, frame and chunk progress updates rewrite one
stderr line instead of printing a new `progress ...` line for every update.

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
