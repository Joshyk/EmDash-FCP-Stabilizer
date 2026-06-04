# Stabilizer FxPlug

FxPlug 4 source for moving the Stabilizer workflow out of CommandPost GUI keyframe writing
and into a native Final Cut Pro / Motion effect.

This is intentionally separate from the existing CommandPost plugin. The Lua/Python workflow
remains available, but this target is the native FxPlug path that avoids writing Final Cut Pro
Transform keyframes.

## Current Scope

- Adds an FxPlug 4 tileable effect named `Stabilizer Transform`.
- Uses Metal to render a transformed source texture.
- Exposes manual transform parameters plus auto stabilization controls.
- Requests a near-frame cluster around the current render time plus a 6-second analysis
  window through `scheduleInputs`.
- Estimates low-resolution global X/Y motion and roll from the requested frames.
- Treats Z stabilization as dynamic scale, so X/Y/Z and rotation are corrected without
  writing Final Cut Pro Transform keyframes.
- Smooths panning by comparing the current path against the average path inside the 6-second
  time-weighted window, while near-frame samples catch fine gimbal jitter.
- Includes a minimal wrapper app source/resource set under `WrapperApp/`.

The current implementation analyzes `kCVPixelFormatType_32BGRA`,
`kCVPixelFormatType_32RGBA`, `kCVPixelFormatType_32ARGB`,
`kCVPixelFormatType_64RGBAHalf`, `kCVPixelFormatType_64RGBALE`, and
`kCVPixelFormatType_128RGBAFloat` source frames. If the host supplies a different pixel
format, auto analysis returns identity for that render.

## Local SDK

This machine has:

```text
/Library/Developer/SDKs/FxPlug.sdk
/Library/Developer/Xcode/Templates/FxPlug/FxPlug 4.xctemplate
```

Full Xcode is still required for project generation and build. At the time this scaffold was
first added, `xcodebuild` was unavailable because `xcode-select` pointed at Command Line Tools:

```text
/Library/Developer/CommandLineTools
```

After installing Xcode, this machine was switched to:

```text
/Applications/Xcode.app/Contents/Developer
```

The Xcode 26.5 Metal toolchain was installed with:

```sh
xcodebuild -downloadComponent MetalToolchain
```

## Build Path

Build the wrapper app and embedded pluginkit:

```sh
xcodebuild \
  -project fxplug/StabilizerFxPlug/StabilizerFxPlug.xcodeproj \
  -scheme StabilizerFxPlug \
  -configuration Debug \
  -derivedDataPath /tmp/StabilizerFxPlugDerived \
  build
```

The `StabilizerFxPlug` shared scheme runs a build post-action after every successful
build. It installs a persistent copy of the Debug app to:

```text
~/Applications/StabilizerFxPlug.app
```

and registers the embedded FxPlug with PluginKit and LaunchServices. The script also
unregisters the temporary DerivedData app path so Final Cut Pro resolves the effect from
the persistent `~/Applications` copy.

If Final Cut Pro is already running during a rebuild, restart Final Cut Pro before checking
for the updated effect in the Effects browser.

The intermediate Debug app is written to:

```text
/tmp/StabilizerFxPlugDerived/Build/Products/Debug/StabilizerFxPlug.app
```

The app embeds:

```text
Contents/PlugIns/StabilizerFxPlug XPC Service.pluginkit
```

To rerun the install/registration step without rebuilding:

```sh
fxplug/StabilizerFxPlug/scripts/install_debug_app.sh \
  /tmp/StabilizerFxPlugDerived/Build/Products/Debug/StabilizerFxPlug.app
```

## Stabilization Model

- `Auto Stabilize`: enables frame analysis and automatic compensation.
- `Strength`: master multiplier for automatic X/Y/Z and rotation compensation.
- `XYZ Strength`: multiplier for automatic X/Y translation and Z scale.
- `Rotation Strength`: multiplier for automatic roll compensation.
- `Pan Smooth Seconds`: defaults to `6.0`; the requested frame window is centered on the
  render time and pan motion is smoothed against that window. The plugin also requests
  near-frame samples around the render time so small gimbal jitter can still drive X/Y/Z
  and rotation compensation.
- `Debug Overlay`: normally off. When enabled, the top-left bars visualize automatic X, Y,
  Z-scale, and rotation compensation so Final Cut Pro runtime analysis can be checked.
- `Offset X`, `Offset Y`, `Rotation Degrees`, and `Scale Percent`: manual trim controls
  applied on top of automatic compensation.
