# Stabilizer FxPlug

FxPlug 4 source for moving the Stabilizer workflow out of CommandPost GUI keyframe writing
and into a native Final Cut Pro / Motion effect.

This is intentionally separate from the existing CommandPost plugin. The Lua/Python workflow
remains available, but this target is the native FxPlug path that avoids writing Final Cut Pro
Transform keyframes.

## Current Scope

- Adds an FxPlug 4 tileable effect named `Stabilizer Transform`.
- Uses Metal to render a transformed source texture.
- Exposes auto stabilization controls without manual transform trim parameters.
- Adds `Analysis Source` with explicit `Host Analysis` and `Live Frames` paths. The default
  long-term path is `Host Analysis`.
- Uses Final Cut Pro's FxPlug analysis infrastructure in `Host Analysis` mode, requesting a
  forward GPU analysis and storing analyzed low-resolution frames in the plug-in runtime.
  `Start Host Analysis` explicitly starts or restarts that request from the inspector.
- Requests a near-frame cluster around the current render time plus the `Pan Smooth Seconds`
  analysis window through `scheduleInputs` only when `Analysis Source` is `Live Frames`.
- Estimates low-resolution global X/Y motion, roll, yaw/pitch proxy motion, shear,
  perspective warp, crop safety, and blur amount from the requested frames.
- Treats Z stabilization as dynamic scale and yaw/pitch as image-space proxy values, so
  X/Y/Z, rotation, shear, and perspective are corrected without writing Final Cut Pro
  Transform keyframes.
- Smooths panning by comparing the current path against the average path inside the
  user-entered `Pan Smooth Seconds` time-weighted window, while near-frame samples catch
  fine gimbal jitter.
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
/Applications/StabilizerFxPlug.app
```

and registers the embedded FxPlug with PluginKit and LaunchServices. The script also
unregisters the old `~/Applications` install and the temporary DerivedData app path so
Final Cut Pro resolves the effect from the persistent `/Applications` copy.

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
- `XYZ Strength`: multiplier for automatic X/Y translation, Z scale, shear, perspective,
  and yaw/pitch proxy compensation.
- `Rotation Strength`: multiplier for automatic roll compensation.
- `Pan Smooth Seconds`: text field, defaults to `6`; positive numeric values define the
  centered panning window. The slider remains as a fallback for older templates or empty
  text input. Large windows automatically use wider-spaced samples so render-time requests
  stay bounded while the smoothing window remains the entered duration.
- `Analysis Source`: defaults to `Host Analysis`. `Host Analysis` uses Final Cut Pro's
  FxPlug analysis infrastructure and requests GPU analysis frames from the host. `Live
  Frames` requests the analysis window during render. Incomplete host analysis renders
  identity for that source instead of silently switching to Live Frames.
- `Start Host Analysis`: clears any stored host-analysis frames and asks Final Cut Pro to
  start a forward GPU analysis for this effect.
- `Debug Overlay`: normally off. When enabled, the top-left bars visualize automatic X, Y,
  Z-scale, rotation, yaw/pitch proxy, shear, perspective, and blur diagnostics so Final Cut
  Pro runtime analysis can be checked.
