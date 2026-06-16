# Stabilizer Event Analyzer

Local Event FCPXMLD analyzer for Tokyo Walking Stabilizer.

The workflow is:

1. Export an Event or Project from Final Cut Pro as FCPXMLD.
2. Open this local Web UI and select one or more `.fcpxmld` packages or
   `Info.fcpxml` files.
3. Choose an export from the selected file list, then select one or more Event
   media assets.
4. Select the Event folder or final Tokyo Walking Stabilizer cache root with the
   macOS folder picker.
5. Run serial analysis for the full media duration of each selected asset.
6. Write schema-compatible Tokyo Walking Stabilizer persisted cache files to an
   explicit Event cache root.
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

## Run

From the repository root:

```sh
cd Stabilizer-Event-Analyzer/node_web
npm start
```

Then open `http://127.0.0.1:3091`.

## Cache Root

Use `Select Event Folder` in the Web UI and choose either the Event folder,
`Analysis Files`, or the final cache root:

```text
SomeEvent/
SomeEvent/Analysis Files/
SomeEvent/Analysis Files/TokyoWalkingStabilizerHostAnalysis/
```

The tool never falls back to Application Support or any shared cache location.
