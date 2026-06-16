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
motion search. Parallel media readers may be used for a single selected asset
to keep the GPU fed, but they are disabled when multiple assets are selected so
selected clips remain strictly serial.

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
