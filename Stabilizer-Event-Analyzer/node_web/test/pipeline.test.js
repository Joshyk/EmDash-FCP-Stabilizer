"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");
const { pathToFileURL } = require("node:url");

const repoRoot = path.resolve(__dirname, "../..");
const fixture = path.join(repoRoot, "fixtures", "minimal-event.fcpxmld");

function hasCommand(command) {
  return spawnSync("bash", ["-lc", `command -v ${command}`], { encoding: "utf8" }).status === 0;
}

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  return JSON.parse(result.stdout);
}

function analysisResult(assetId = "r2", name = "P1000307") {
  return {
    assetId,
    name,
    footageFileName: `${name}.mov`,
    mediaPath: `/tmp/${name}.mov`,
    mediaKind: "original-media",
    sourceMediaFingerprint: "aaa:bbb:ccc",
    cacheFileName: `host-analysis-v2-${name}.json`,
    cacheIdentity: `19:0:6006:20:1920:1080:300:aaa:bbb:ccc:end6006:${name}`,
    cacheSchemaVersion: 19,
    durationSeconds: 10.01,
    sampleScalePercent: 10,
    sampleWidth: 192,
    sampleHeight: 108,
    frameCount: 300,
    rangeStartSeconds: 0,
    rangeDurationSeconds: 10.01,
    rangeEndSeconds: 10.01,
    frameDurationSeconds: 1001 / 30000,
    firstFingerprint: "aaa",
    middleFingerprint: "bbb",
    lastFingerprint: "ccc",
    preparedMotionPath: true,
  };
}

function writeCachePayload(root, result = analysisResult()) {
  const cacheRoot = path.join(root, "Analysis Files", "TokyoWalkingStabilizerHostAnalysis");
  const cachesDir = path.join(cacheRoot, "caches");
  fs.mkdirSync(cachesDir, { recursive: true });
  fs.writeFileSync(
    path.join(cachesDir, result.cacheFileName),
    JSON.stringify({
      schemaVersion: result.cacheSchemaVersion,
      frames: Array.from({ length: result.frameCount }, (_, index) => ({ time: index * result.frameDurationSeconds })),
      pathX: Array.from({ length: result.frameCount }, () => 0),
      pathY: Array.from({ length: result.frameCount }, () => 0),
      pathRoll: Array.from({ length: result.frameCount }, () => 0),
    }),
    "utf8"
  );
  fs.writeFileSync(
    path.join(cacheRoot, "host-analysis-index-v2.json"),
    JSON.stringify({
      schemaVersion: result.cacheSchemaVersion,
      entries: [{
        cacheIdentity: result.cacheIdentity,
        cacheFileName: result.cacheFileName,
        frameCount: result.frameCount,
      }],
    }),
    "utf8"
  );
  return cacheRoot;
}

function writeFcpxmld(packageDir, assetXml) {
  fs.mkdirSync(packageDir, { recursive: true });
  fs.writeFileSync(
    path.join(packageDir, "Info.fcpxml"),
    `<?xml version="1.0" encoding="UTF-8"?>
<fcpxml version="1.11">
  <resources>
    <format id="r1" name="FFVideoFormat1080p30" frameDuration="1001/30000s" width="1920" height="1080"/>
    ${assetXml}
  </resources>
  <library>
    <event name="ProxyCheck"/>
  </library>
</fcpxml>
`,
    "utf8"
  );
}

test("list_event_assets reads Event media assets", () => {
  const payload = run("python3", ["scripts/list_event_assets.py", "--fcpxml", fixture]);
  assert.equal(payload.status, "ok");
  assert.equal(payload.assetCount, 1);
  assert.equal(payload.assets[0].assetId, "r2");
  assert.equal(payload.assets[0].name, "P1000307");
  assert.equal(payload.assets[0].mediaKind, "original-media");
  assert.equal(payload.assets[0].durationTimecode, "00:00:10:00");
});

test("list_event_assets reads original media clips from an FCP library bundle", { skip: !(hasCommand("ffmpeg") && hasCommand("ffprobe")) }, () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-fcpbundle-source-"));
  const bundle = path.join(tmp, "Library.fcpbundle");
  const originalMedia = path.join(bundle, "Event A", "Original Media");
  const proxyMedia = path.join(bundle, "Event A", "Transcoded Media", "Proxy Media");
  fs.mkdirSync(originalMedia, { recursive: true });
  fs.mkdirSync(proxyMedia, { recursive: true });
  fs.writeFileSync(
    path.join(bundle, "Settings.plist"),
    `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>colorProcessingMode</key>
  <integer>2</integer>
</dict>
</plist>
`,
    "utf8"
  );
  const clipPath = path.join(originalMedia, "LibraryClip.mov");
  const proxyPath = path.join(proxyMedia, "ProxyClip.mov");
  fs.writeFileSync(proxyPath, "");
  const ffmpeg = spawnSync("ffmpeg", [
    "-hide_banner",
    "-loglevel",
    "error",
    "-f",
    "lavfi",
    "-i",
    "testsrc=size=160x90:rate=30",
    "-frames:v",
    "30",
    "-an",
    "-pix_fmt",
    "yuv420p",
    "-c:v",
    "mpeg4",
    clipPath,
  ], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  assert.equal(ffmpeg.status, 0, ffmpeg.stderr || ffmpeg.stdout);

  const payload = run("python3", ["scripts/list_event_assets.py", "--fcpxml", bundle]);
  assert.equal(payload.status, "ok");
  assert.equal(payload.packagePath, fs.realpathSync(bundle));
  assert.match(payload.infoPath, /fcpbundle_sources/);
  assert.deepEqual(payload.eventNames, ["Event A"]);
  assert.equal(payload.assetCount, 1);
  const info = fs.readFileSync(payload.infoPath, "utf8");
  const sourceManifest = JSON.parse(fs.readFileSync(path.join(path.dirname(payload.infoPath), "source-manifest.json"), "utf8"));
  assert.equal(sourceManifest.syntheticSchemaVersion, 3);
  assert.equal(sourceManifest.colorProcessing, "wide-hdr");
  assert.match(info, /<library colorProcessing="wide-hdr">/);
  assert.doesNotMatch(info, /name="FFVideoFormat160x90"/);
  assert.equal(payload.assets[0].name, "LibraryClip");
  assert.equal(payload.assets[0].eventName, "Event A");
  assert.equal(payload.assets[0].mediaKind, "original-media");
  assert.equal(payload.assets[0].mediaPath, fs.realpathSync(clipPath));
  assert.equal(payload.assets[0].supported, true);
  assert.equal(payload.assets[0].width, 160);
  assert.equal(payload.assets[0].height, 90);
  assert.equal(payload.assets[0].frameDuration, "1/30s");

  const analysis = analysisResult(payload.assets[0].assetId, "LibraryClip");
  analysis.mediaPath = "/Volumes/External Media/LibraryClip.mov";
  const cacheRoot = writeCachePayload(tmp, analysis);
  const analysisPath = path.join(tmp, "analysis.json");
  fs.writeFileSync(analysisPath, JSON.stringify({ status: "ok", cacheRoot, results: [analysis] }), "utf8");
  const build = run("python3", [
    "scripts/build_stabilizer_fcpxml_import.py",
    "--source-fcpxml",
    bundle,
    "--analysis-json",
    analysisPath,
    "--output-dir",
    tmp,
    "--only-analyzed-assets",
    "--per-footage-packages",
  ]);
  const pkg = build.packages[0];
  const manifest = JSON.parse(fs.readFileSync(pkg.manifestPath, "utf8"));
  assert.equal(manifest.eventName, "Event A");
  assert.equal(manifest.eventRoot, fs.realpathSync(path.join(bundle, "Event A")));
});

test("fcpxml_common maps ffprobe color metadata to FCPXML colorSpace labels", () => {
  const script = `
import sys
sys.path.insert(0, "scripts")
from fcpxml_common import fcp_color_space
assert fcp_color_space("bt2020", "arib-std-b67", "bt2020nc") == "9-18-9 (Rec. 2020 HLG)"
assert fcp_color_space("bt709", "bt709", "bt709") == "1-1-1 (Rec. 709)"
assert fcp_color_space("smpte170m", "bt709", "bt709") is None
`;
  const result = spawnSync("python3", ["-c", script], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);
});

test("list_event_assets refuses proxy-only media reps", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-proxy-only-"));
  const pkg = path.join(tmp, "ProxyOnly.fcpxmld");
  const proxyPath = path.join(tmp, "proxy.mov");
  fs.writeFileSync(proxyPath, "");
  writeFcpxmld(
    pkg,
    `<asset id="r2" name="ProxyOnly" start="0s" duration="30030/30000s" hasVideo="1" format="r1">
      <media-rep kind="proxy-media" src="${pathToFileURL(proxyPath).href}"/>
    </asset>`
  );
  const payload = run("python3", ["scripts/list_event_assets.py", "--fcpxml", pkg]);
  assert.equal(payload.status, "ok");
  assert.equal(payload.assetCount, 1);
  assert.equal(payload.assets[0].supported, false);
  assert.equal(payload.assets[0].mediaPath, null);
  assert.match(payload.assets[0].unsupported, /no original-media media-rep/);
  assert.match(payload.assets[0].unsupported, /refusing proxy-media/);
});

test("list_event_assets chooses original media over proxy media", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-original-priority-"));
  const pkg = path.join(tmp, "OriginalPriority.fcpxmld");
  const proxyPath = path.join(tmp, "proxy.mov");
  const originalPath = path.join(tmp, "original.mov");
  fs.writeFileSync(proxyPath, "");
  fs.writeFileSync(originalPath, "");
  writeFcpxmld(
    pkg,
    `<asset id="r2" name="OriginalPriority" start="0s" duration="30030/30000s" hasVideo="1" format="r1">
      <media-rep kind="proxy-media" src="${pathToFileURL(proxyPath).href}"/>
      <media-rep kind="original-media" src="${pathToFileURL(originalPath).href}"/>
    </asset>`
  );
  const payload = run("python3", ["scripts/list_event_assets.py", "--fcpxml", pkg]);
  assert.equal(payload.status, "ok");
  assert.equal(payload.assets[0].supported, true);
  assert.equal(payload.assets[0].mediaKind, "original-media");
  assert.equal(payload.assets[0].mediaPath, originalPath);
});

test("list_event_assets refuses direct asset src inside FCP Proxy Media", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-direct-proxy-src-"));
  const pkg = path.join(tmp, "DirectProxy.fcpxmld");
  const proxyDir = path.join(tmp, "Transcoded Media", "Proxy Media");
  const proxyPath = path.join(proxyDir, "proxy.mov");
  fs.mkdirSync(proxyDir, { recursive: true });
  fs.writeFileSync(proxyPath, "");
  writeFcpxmld(
    pkg,
    `<asset id="r2" name="DirectProxy" start="0s" duration="30030/30000s" hasVideo="1" format="r1" src="${pathToFileURL(proxyPath).href}"/>`
  );
  const payload = run("python3", ["scripts/list_event_assets.py", "--fcpxml", pkg]);
  assert.equal(payload.status, "ok");
  assert.equal(payload.assets[0].mediaKind, "asset-src");
  assert.equal(payload.assets[0].supported, false);
  assert.match(payload.assets[0].unsupported, /FCP Proxy Media/);
});

test("analyze_event_assets refuses stale prebuilt native analyzer", () => {
  const script = String.raw`
import importlib.util
import os
import pathlib
import sys
import tempfile
import time

script = pathlib.Path("scripts/analyze_event_assets.py").resolve()
sys.path.insert(0, str(script.parent))
spec = importlib.util.spec_from_file_location("analyze_event_assets", script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as tmp:
    package = pathlib.Path(tmp) / "native_analyzer"
    source_dir = package / "Sources" / "StabilizerEventAnalyzer"
    source_dir.mkdir(parents=True)
    source = source_dir / "main.swift"
    source.write_text("print(\"new\")\n", encoding="utf-8")
    (package / "Package.swift").write_text("// package\n", encoding="utf-8")
    executable = package / ".build" / "arm64-apple-macosx" / "release" / "StabilizerEventAnalyzer"
    executable.parent.mkdir(parents=True)
    executable.write_text("#!/bin/sh\n", encoding="utf-8")
    executable.chmod(0o755)
    now = time.time()
    os.utime(executable, (now - 100, now - 100))
    os.utime(source, (now, now))

    module.NATIVE_PACKAGE = package
    module.shutil.which = lambda name: "/usr/bin/swift"
    stale_command = module.swift_command(pathlib.Path("/tmp/plan.json"), False)
    if stale_command[0] != "/usr/bin/swift":
        raise AssertionError(stale_command)

    os.utime(executable, (now + 100, now + 100))
    fresh_command = module.swift_command(pathlib.Path("/tmp/plan.json"), False)
    if fresh_command[0] != str(executable):
        raise AssertionError(fresh_command)
`;
  const result = spawnSync("python3", ["-c", script], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  assert.equal(result.status, 0, result.stderr || result.stdout);
});

test("build_stabilizer_fcpxml_import inserts Stabilizer filter", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-import-test-"));
  const analysisPath = path.join(tmp, "analysis.json");
  fs.writeFileSync(
    analysisPath,
    JSON.stringify({
      status: "ok",
      results: [
        {
          assetId: "r2",
          cacheIdentity: "18:0:6006:20:1920:1080:300:aaa:bbb:ccc:end6006:P1000307",
          cacheSchemaVersion: 19,
          sampleScalePercent: 100,
          sampleWidth: 1920,
          sampleHeight: 1080,
          frameCount: 300,
        },
      ],
    }),
    "utf8"
  );
  const payload = run("python3", [
    "scripts/build_stabilizer_fcpxml_import.py",
    "--source-fcpxml",
    fixture,
    "--analysis-json",
    analysisPath,
    "--output-dir",
    tmp,
  ]);
  assert.equal(payload.status, "ok");
  assert.equal(payload.insertedFilters, 1);
  const info = fs.readFileSync(path.join(payload.outputPackage, "Info.fcpxml"), "utf8");
  assert.match(info, /Tokyo Walking Stabilizer/);
  assert.match(info, /Host Analysis Cache Identity/);
  assert.doesNotMatch(info, /nameOverride=/);
  assert.doesNotMatch(info, /videoOverride=/);
});

test("build_stabilizer_fcpxml_import attaches video refs to parent clips", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-video-ref-test-"));
  const pkg = path.join(tmp, "VideoRef.fcpxmld");
  fs.mkdirSync(pkg, { recursive: true });
  fs.writeFileSync(
    path.join(pkg, "Info.fcpxml"),
    `<?xml version="1.0" encoding="UTF-8"?>
<fcpxml version="1.11">
  <resources>
    <format id="r1" name="FFVideoFormat1080p30" frameDuration="1001/30000s" width="1920" height="1080"/>
    <asset id="r2" name="P1000307" start="0s" duration="300300/30000s" hasVideo="1" format="r1" src="file:///tmp/P1000307.mov"/>
  </resources>
  <library>
    <event name="VideoRef">
      <project name="VideoRef Project">
        <sequence format="r1" duration="300300/30000s" tcStart="0s" tcFormat="NDF">
          <spine>
            <clip name="Wrapped video" offset="0s" start="0s" duration="300300/30000s">
              <video ref="r2" offset="0s" start="0s" duration="300300/30000s">
                <adjust-stabilization enabled="0" type="smoothCam"/>
                <filter-video ref="r3" name="Tokyo Walking Stabilizer"/>
              </video>
            </clip>
          </spine>
        </sequence>
      </project>
    </event>
  </library>
</fcpxml>
`,
    "utf8"
  );
  const analysisPath = path.join(tmp, "analysis.json");
  fs.writeFileSync(
    analysisPath,
    JSON.stringify({
      status: "ok",
      results: [
        {
          assetId: "r2",
          cacheIdentity: "18:0:6006:20:1920:1080:300:aaa:bbb:ccc:end6006:P1000307",
          cacheSchemaVersion: 19,
          sampleScalePercent: 100,
          sampleWidth: 1920,
          sampleHeight: 1080,
          frameCount: 300,
        },
      ],
    }),
    "utf8"
  );
  const payload = run("python3", [
    "scripts/build_stabilizer_fcpxml_import.py",
    "--source-fcpxml",
    pkg,
    "--analysis-json",
    analysisPath,
    "--output-dir",
    tmp,
  ]);
  assert.equal(payload.status, "ok");
  assert.equal(payload.insertedFilters, 1);
  assert.equal(payload.removedExistingFilters, 1);
  const info = fs.readFileSync(path.join(payload.outputPackage, "Info.fcpxml"), "utf8");
  const videoBody = info.match(/<video[^>]*ref="r2"[\s\S]*?<\/video>/)[0];
  assert.doesNotMatch(videoBody, /Tokyo Walking Stabilizer/);
  assert.match(info, /<\/video>\s*<filter-video ref="r\d+" name="Tokyo Walking Stabilizer"/);
});

test("build_stabilizer_fcpxml_import preserves marker order before filters", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-marker-order-test-"));
  const pkg = path.join(tmp, "MarkerOrder.fcpxmld");
  fs.mkdirSync(pkg, { recursive: true });
  fs.writeFileSync(
    path.join(pkg, "Info.fcpxml"),
    `<?xml version="1.0" encoding="UTF-8"?>
<fcpxml version="1.11">
  <resources>
    <format id="r1" name="FFVideoFormat1080p30" frameDuration="1001/30000s" width="1920" height="1080"/>
    <asset id="r2" name="P1000307" start="0s" duration="300300/30000s" hasVideo="1" format="r1" src="file:///tmp/P1000307.mov"/>
    <effect id="r3" name="Existing Effect" uid="FxPlug:EXISTING"/>
  </resources>
  <library>
    <event name="MarkerOrder">
      <project name="MarkerOrder Project">
        <sequence format="r1" duration="300300/30000s" tcStart="0s" tcFormat="NDF">
          <spine>
            <asset-clip name="P1000307" ref="r2" offset="0s" start="0s" duration="300300/30000s">
              <adjust-colorConform enabled="1"/>
              <adjust-volume amount="-96dB"/>
              <marker start="0s" duration="1001/30000s" value="turn"/>
              <filter-video ref="r3" name="Existing Effect"/>
            </asset-clip>
          </spine>
        </sequence>
      </project>
    </event>
  </library>
</fcpxml>
`,
    "utf8"
  );
  const analysisPath = path.join(tmp, "analysis.json");
  fs.writeFileSync(
    analysisPath,
    JSON.stringify({
      status: "ok",
      results: [
        {
          assetId: "r2",
          cacheIdentity: "18:0:6006:20:1920:1080:300:aaa:bbb:ccc:end6006:P1000307",
          cacheSchemaVersion: 19,
          sampleScalePercent: 100,
          sampleWidth: 1920,
          sampleHeight: 1080,
          frameCount: 300,
        },
      ],
    }),
    "utf8"
  );
  const payload = run("python3", [
    "scripts/build_stabilizer_fcpxml_import.py",
    "--source-fcpxml",
    pkg,
    "--analysis-json",
    analysisPath,
    "--output-dir",
    tmp,
  ]);
  assert.equal(payload.status, "ok");
  assert.equal(payload.insertedFilters, 1);
  const info = fs.readFileSync(path.join(payload.outputPackage, "Info.fcpxml"), "utf8");
  assert.match(
    info,
    /<marker[^>]*value="turn"[^>]*\s*\/>\s*<filter-video ref="r\d+" name="Tokyo Walking Stabilizer"[\s\S]*?<\/filter-video><filter-video ref="r3" name="Existing Effect"/
  );
});

test("build_stabilizer_fcpxml_import removes legacy Stabilizer Transform filters", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-legacy-filter-test-"));
  const pkg = path.join(tmp, "LegacyFilter.fcpxmld");
  fs.mkdirSync(pkg, { recursive: true });
  fs.writeFileSync(
    path.join(pkg, "Info.fcpxml"),
    `<?xml version="1.0" encoding="UTF-8"?>
<fcpxml version="1.11">
  <resources>
    <format id="r1" name="FFVideoFormat1080p30" frameDuration="1001/30000s" width="1920" height="1080"/>
    <asset id="r2" name="P1000307" start="0s" duration="300300/30000s" hasVideo="1" format="r1" src="file:///tmp/P1000307.mov"/>
    <asset id="r4" name="Other" start="0s" duration="300300/30000s" hasVideo="1" format="r1" src="file:///tmp/Other.mov"/>
    <effect id="r5" name="Stabilizer Transform" uid="~/Effects.localized/Emdash Studios/Stabilizer Transform/Stabilizer Transform.moef"/>
  </resources>
  <library>
    <event name="LegacyFilter">
      <project name="LegacyFilter Project">
        <sequence format="r1" duration="600600/30000s" tcStart="0s" tcFormat="NDF">
          <spine>
            <asset-clip name="P1000307" ref="r2" offset="0s" start="0s" duration="300300/30000s">
              <filter-video ref="r5" name="Stabilizer Transform"/>
            </asset-clip>
            <asset-clip name="Other" ref="r4" offset="300300/30000s" start="0s" duration="300300/30000s">
              <filter-video ref="r5" name="Stabilizer Transform"/>
            </asset-clip>
          </spine>
        </sequence>
      </project>
    </event>
  </library>
</fcpxml>
`,
    "utf8"
  );
  const analysisPath = path.join(tmp, "analysis.json");
  fs.writeFileSync(
    analysisPath,
    JSON.stringify({
      status: "ok",
      results: [
        {
          assetId: "r2",
          cacheIdentity: "18:0:6006:20:1920:1080:300:aaa:bbb:ccc:end6006:P1000307",
          cacheSchemaVersion: 19,
          sampleScalePercent: 100,
          sampleWidth: 1920,
          sampleHeight: 1080,
          frameCount: 300,
        },
      ],
    }),
    "utf8"
  );
  const payload = run("python3", [
    "scripts/build_stabilizer_fcpxml_import.py",
    "--source-fcpxml",
    pkg,
    "--analysis-json",
    analysisPath,
    "--output-dir",
    tmp,
  ]);
  assert.equal(payload.status, "ok");
  assert.equal(payload.insertedFilters, 1);
  assert.equal(payload.removedExistingFilters, 2);
  const info = fs.readFileSync(path.join(payload.outputPackage, "Info.fcpxml"), "utf8");
  assert.doesNotMatch(info, /Stabilizer Transform/);
  assert.match(info, /Tokyo Walking Stabilizer/);
});

test("build_stabilizer_fcpxml_import can emit only analyzed assets", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-analyzed-only-test-"));
  const pkg = path.join(tmp, "AnalyzedOnly.fcpxmld");
  fs.mkdirSync(pkg, { recursive: true });
  fs.writeFileSync(
    path.join(pkg, "Info.fcpxml"),
    `<?xml version="1.0" encoding="UTF-8"?>
<fcpxml version="1.11">
  <resources>
    <format id="r1" name="FFVideoFormat1080p30" frameDuration="1001/30000s" width="1920" height="1080"/>
    <asset id="r2" name="P1000307" start="3600s" duration="300300/30000s" hasVideo="1" format="r1" src="file:///tmp/P1000307.mov"/>
    <asset id="r4" name="Other" start="0s" duration="300300/30000s" hasVideo="1" format="r1" src="file:///tmp/Other.mov"/>
    <effect id="r5" name="Existing Effect" uid="FxPlug:EXISTING"/>
  </resources>
  <library colorProcessing="wide-hdr">
    <event name="AnalyzedOnly">
      <asset-clip name="P1000307" ref="r2" start="3600s" duration="300300/30000s" format="r1">
        <adjust-colorConform enabled="1"/>
      </asset-clip>
      <project name="Large Existing Project">
        <sequence format="r1" duration="600600/30000s" tcStart="0s" tcFormat="NDF">
          <spine>
            <asset-clip name="P1000307" ref="r2" offset="0s" start="0s" duration="300300/30000s">
              <filter-video ref="r5" name="Existing Effect"/>
            </asset-clip>
            <asset-clip name="Other" ref="r4" offset="300300/30000s" start="0s" duration="300300/30000s">
              <filter-video ref="r5" name="Existing Effect"/>
            </asset-clip>
          </spine>
        </sequence>
      </project>
    </event>
  </library>
</fcpxml>
`,
    "utf8"
  );
  const analysisPath = path.join(tmp, "analysis.json");
  fs.writeFileSync(
    analysisPath,
    JSON.stringify({
      status: "ok",
      results: [
        {
          assetId: "r2",
          cacheIdentity: "18:0:6006:20:1920:1080:300:aaa:bbb:ccc:end6006:P1000307",
          cacheSchemaVersion: 19,
          sampleScalePercent: 100,
          sampleWidth: 1920,
          sampleHeight: 1080,
          frameCount: 300,
        },
      ],
    }),
    "utf8"
  );
  const payload = run("python3", [
    "scripts/build_stabilizer_fcpxml_import.py",
    "--source-fcpxml",
    pkg,
    "--analysis-json",
    analysisPath,
    "--output-dir",
    tmp,
    "--only-analyzed-assets",
  ]);
  assert.equal(payload.status, "ok");
  assert.equal(payload.onlyAnalyzedAssets, true);
  assert.equal(payload.insertedFilters, 1);
  const info = fs.readFileSync(path.join(payload.outputPackage, "Info.fcpxml"), "utf8");
  assert.match(info, /<library colorProcessing="wide-hdr">/);
  assert.match(info, /<event name="AnalyzedOnly">/);
  assert.doesNotMatch(info, /Tokyo Walking Stabilizer - Analyzed Footage/);
  assert.doesNotMatch(info, /<project/);
  assert.doesNotMatch(info, /<media id="r\d+"/);
  assert.doesNotMatch(info, /<ref-clip/);
  assert.doesNotMatch(info, /<video/);
  const eventAssetIndex = info.indexOf('<asset-clip ref="r2"');
  assert.ok(eventAssetIndex !== -1);
  assert.match(info, /<asset[^>]+id="r2"[^>]+start="3600s"/);
  assert.equal((info.match(/<asset-clip[^>]+ref="r2"[^>]+start="3600s"/g) || []).length, 1);
  assert.doesNotMatch(info, /Large Existing Project/);
  assert.doesNotMatch(info, /Other/);
  assert.match(info, /<effect id="r5" name="Existing Effect"/);
  assert.match(
    info,
    /<filter-video ref="r\d+" name="Tokyo Walking Stabilizer"[\s\S]*?<\/filter-video>\s*<filter-video ref="r5" name="Existing Effect"\s*\/>/
  );
  assert.equal((info.match(/<filter-video[^>]+name="Tokyo Walking Stabilizer"/g) || []).length, 1);
});

test("build_stabilizer_fcpxml_import emits one package directory per footage", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-per-footage-test-"));
  const analysisPath = path.join(tmp, "analysis.json");
  const result = analysisResult();
  const cacheRoot = writeCachePayload(tmp, result);
  fs.writeFileSync(
    analysisPath,
    JSON.stringify({
      status: "ok",
      cacheRoot,
      results: [result],
    }),
    "utf8"
  );
  const payload = run("python3", [
    "scripts/build_stabilizer_fcpxml_import.py",
    "--source-fcpxml",
    fixture,
    "--analysis-json",
    analysisPath,
    "--output-dir",
    tmp,
    "--only-analyzed-assets",
    "--per-footage-packages",
  ]);
  assert.equal(payload.status, "ok");
  assert.equal(payload.perFootagePackages, true);
  assert.equal(payload.packages.length, 1);
  const pkg = payload.packages[0];
  assert.match(path.basename(pkg.packageDirectory), /^P1000307__sample10__schema19__300f__/);
  assert.equal(path.basename(pkg.outputPackage), "P1000307.fcpxmld");
  assert.equal(path.basename(pkg.manifestPath), "P1000307.analysis-manifest.json");
  const manifest = JSON.parse(fs.readFileSync(pkg.manifestPath, "utf8"));
  assert.equal(manifest.footageFileName, "P1000307.mov");
  assert.equal(manifest.eventName, "gh6");
  assert.equal(manifest.sourceMediaFingerprint, "aaa:bbb:ccc");
  assert.equal(manifest.cacheIdentity, analysisResult().cacheIdentity);
  assert.equal(manifest.preparedMotionPath, true);
  assert.equal(manifest.sourceEffectStack.inheritedFilterCount, 0);
  assert.equal(fs.existsSync(path.join(pkg.packageDirectory, manifest.cachePayloadCacheFile)), true);
  assert.equal(fs.existsSync(path.join(pkg.outputPackage, "Info.fcpxml")), true);
});

test("build_stabilizer_fcpxml_import inherits source effects in per-footage packages", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-per-footage-effects-test-"));
  const pkg = path.join(tmp, "TimelineEffects.fcpxmld");
  fs.mkdirSync(pkg, { recursive: true });
  fs.writeFileSync(
    path.join(pkg, "Info.fcpxml"),
    `<?xml version="1.0" encoding="UTF-8"?>
<fcpxml version="1.11">
  <resources>
    <format id="r1" name="FFVideoFormat1080p30" frameDuration="1001/30000s" width="1920" height="1080"/>
    <asset id="r2" name="P1000307" start="0s" duration="300300/30000s" hasVideo="1" format="r1">
      <media-rep kind="original-media" src="file:///tmp/P1000307.mov"/>
    </asset>
    <effect id="r5" name="Existing Effect" uid="FxPlug:EXISTING"/>
  </resources>
  <library>
    <event name="TimelineEffects">
      <project name="Timeline Effects Project">
        <sequence format="r1" duration="300300/30000s" tcStart="0s" tcFormat="NDF">
          <spine>
            <asset-clip name="P1000307" ref="r2" offset="0s" start="0s" duration="300300/30000s">
              <marker start="0s" duration="1001/30000s" value="keep"/>
              <filter-video ref="r5" name="Existing Effect"/>
            </asset-clip>
          </spine>
        </sequence>
      </project>
    </event>
  </library>
</fcpxml>
`,
    "utf8"
  );
  const analysis = analysisResult();
  const cacheRoot = writeCachePayload(tmp, analysis);
  const analysisPath = path.join(tmp, "analysis.json");
  fs.writeFileSync(
    analysisPath,
    JSON.stringify({ status: "ok", cacheRoot, results: [analysis] }),
    "utf8"
  );
  const build = run("python3", [
    "scripts/build_stabilizer_fcpxml_import.py",
    "--source-fcpxml",
    pkg,
    "--analysis-json",
    analysisPath,
    "--output-dir",
    tmp,
    "--only-analyzed-assets",
    "--per-footage-packages",
  ]);
  assert.equal(build.status, "ok");
  assert.equal(build.packages[0].sourceEffectStack.inheritedFilterCount, 1);
  assert.deepEqual(build.packages[0].sourceEffectStack.inheritedFilterNames, ["Existing Effect"]);
  const builtPackage = build.packages[0];
  const info = fs.readFileSync(path.join(builtPackage.outputPackage, "Info.fcpxml"), "utf8");
  assert.match(info, /<effect id="r5" name="Existing Effect"/);
  assert.match(
    info,
    /<marker[^>]*value="keep"[^>]*\s*\/>\s*<filter-video ref="r\d+" name="Tokyo Walking Stabilizer"[\s\S]*?<\/filter-video>\s*<filter-video ref="r5" name="Existing Effect"\s*\/>/
  );
  const manifest = JSON.parse(fs.readFileSync(builtPackage.manifestPath, "utf8"));
  assert.equal(manifest.sourceEffectStack.inheritedFilterCount, 1);
  assert.deepEqual(manifest.sourceEffectStack.inheritedFilterNames, ["Existing Effect"]);
  assert.equal(manifest.sourceEffectStack.unavailableReason, null);
  const validation = run("python3", [
    "scripts/validate_stabilizer_fcpxml_import.py",
    "--fcpxml",
    builtPackage.outputPackage,
    "--manifest",
    builtPackage.manifestPath,
    "--output",
    builtPackage.validationPath,
  ]);
  assert.equal(validation.status, "pass");
  assert.equal(validation.importReady, true);
});

test("validate_stabilizer_fcpxml_import passes generated per-footage package", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-validator-pass-test-"));
  const analysisPath = path.join(tmp, "analysis.json");
  const analysis = analysisResult();
  const cacheRoot = writeCachePayload(tmp, analysis);
  fs.writeFileSync(
    analysisPath,
    JSON.stringify({ status: "ok", cacheRoot, results: [analysis] }),
    "utf8"
  );
  const build = run("python3", [
    "scripts/build_stabilizer_fcpxml_import.py",
    "--source-fcpxml",
    fixture,
    "--analysis-json",
    analysisPath,
    "--output-dir",
    tmp,
    "--only-analyzed-assets",
    "--per-footage-packages",
  ]);
  const pkg = build.packages[0];
  const validation = run("python3", [
    "scripts/validate_stabilizer_fcpxml_import.py",
    "--fcpxml",
    pkg.outputPackage,
    "--manifest",
    pkg.manifestPath,
    "--output",
    pkg.validationPath,
  ]);
  assert.equal(validation.status, "pass");
  assert.equal(validation.importReady, true);
  assert.equal(fs.existsSync(pkg.validationPath), true);
});

test("install_stabilizer_package_cache infers Event root from manifest mediaPath", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-install-cache-test-"));
  const eventRoot = path.join(tmp, "Library.fcpbundle", "Event A");
  fs.mkdirSync(path.join(eventRoot, "Original Media"), { recursive: true });
  const analysisPath = path.join(tmp, "analysis.json");
  const analysis = analysisResult();
  analysis.mediaPath = path.join(eventRoot, "Original Media", "P1000307.mov");
  const cacheRoot = writeCachePayload(tmp, analysis);
  fs.writeFileSync(
    analysisPath,
    JSON.stringify({ status: "ok", cacheRoot, results: [analysis] }),
    "utf8"
  );
  const build = run("python3", [
    "scripts/build_stabilizer_fcpxml_import.py",
    "--source-fcpxml",
    fixture,
    "--analysis-json",
    analysisPath,
    "--output-dir",
    tmp,
    "--only-analyzed-assets",
    "--per-footage-packages",
  ]);
  const pkg = build.packages[0];
  const install = run("python3", [
    "scripts/install_stabilizer_package_cache.py",
    "--manifest",
    pkg.manifestPath,
  ]);
  assert.equal(install.status, "ok");
  const resolvedEventRoot = fs.realpathSync(eventRoot);
  assert.equal(install.eventRoot, resolvedEventRoot);
  assert.equal(install.cacheRoot, path.join(resolvedEventRoot, "Analysis Files", "TokyoWalkingStabilizerHostAnalysis"));
  assert.equal(fs.existsSync(path.join(install.cacheRoot, "caches", analysis.cacheFileName)), true);
});

test("install_stabilizer_package_cache uses manifest eventRoot when mediaPath is external", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-install-cache-event-root-test-"));
  const eventRoot = path.join(tmp, "Library.fcpbundle", "Event A");
  fs.mkdirSync(path.join(eventRoot, "Original Media"), { recursive: true });
  const analysisPath = path.join(tmp, "analysis.json");
  const analysis = analysisResult();
  analysis.mediaPath = "/Volumes/External Media/P1000307.mov";
  const cacheRoot = writeCachePayload(tmp, analysis);
  fs.writeFileSync(
    analysisPath,
    JSON.stringify({ status: "ok", cacheRoot, results: [analysis] }),
    "utf8"
  );
  const build = run("python3", [
    "scripts/build_stabilizer_fcpxml_import.py",
    "--source-fcpxml",
    fixture,
    "--analysis-json",
    analysisPath,
    "--output-dir",
    tmp,
    "--only-analyzed-assets",
    "--per-footage-packages",
  ]);
  const pkg = build.packages[0];
  const manifest = JSON.parse(fs.readFileSync(pkg.manifestPath, "utf8"));
  manifest.eventRoot = eventRoot;
  fs.writeFileSync(pkg.manifestPath, JSON.stringify(manifest, null, 2), "utf8");
  const targetCacheRoot = path.join(eventRoot, "Analysis Files", "TokyoWalkingStabilizerHostAnalysis");
  fs.mkdirSync(targetCacheRoot, { recursive: true });
  fs.writeFileSync(
    path.join(targetCacheRoot, "host-analysis-index-v2.json"),
    JSON.stringify({
      schemaVersion: analysis.cacheSchemaVersion,
      entries: [{
        cacheIdentity: "old-cache-identity",
        cacheFileName: "old-cache.json",
      }],
    }),
    "utf8"
  );
  const install = run("python3", [
    "scripts/install_stabilizer_package_cache.py",
    "--manifest",
    pkg.manifestPath,
  ]);
  assert.equal(install.status, "ok");
  const resolvedEventRoot = fs.realpathSync(eventRoot);
  assert.equal(install.eventRoot, resolvedEventRoot);
  assert.equal(install.cacheRoot, path.join(resolvedEventRoot, "Analysis Files", "TokyoWalkingStabilizerHostAnalysis"));
  assert.equal(fs.existsSync(path.join(install.cacheRoot, "caches", analysis.cacheFileName)), true);
  const installedIndex = JSON.parse(fs.readFileSync(path.join(install.cacheRoot, "host-analysis-index-v2.json"), "utf8"));
  assert.equal(installedIndex.entries.some((entry) => entry.cacheIdentity === "old-cache-identity"), true);
  assert.equal(installedIndex.entries.some((entry) => entry.cacheIdentity === analysis.cacheIdentity), true);
});

test("validate_stabilizer_fcpxml_import fails cache identity mismatch before FCP import", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-validator-fail-test-"));
  const analysisPath = path.join(tmp, "analysis.json");
  const analysis = analysisResult();
  const cacheRoot = writeCachePayload(tmp, analysis);
  fs.writeFileSync(
    analysisPath,
    JSON.stringify({ status: "ok", cacheRoot, results: [analysis] }),
    "utf8"
  );
  const build = run("python3", [
    "scripts/build_stabilizer_fcpxml_import.py",
    "--source-fcpxml",
    fixture,
    "--analysis-json",
    analysisPath,
    "--output-dir",
    tmp,
    "--only-analyzed-assets",
    "--per-footage-packages",
  ]);
  const pkg = build.packages[0];
  const manifest = JSON.parse(fs.readFileSync(pkg.manifestPath, "utf8"));
  manifest.cacheIdentity = "wrong-cache-identity";
  fs.writeFileSync(pkg.manifestPath, JSON.stringify(manifest, null, 2), "utf8");
  const result = spawnSync("python3", [
    "scripts/validate_stabilizer_fcpxml_import.py",
    "--fcpxml",
    pkg.outputPackage,
    "--manifest",
    pkg.manifestPath,
    "--output",
    pkg.validationPath,
  ], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  assert.notEqual(result.status, 0);
  const validation = JSON.parse(result.stdout);
  assert.equal(validation.status, "fail");
  assert.equal(validation.importReady, false);
  assert.match(validation.failures.join("\n"), /Cache Identity does not match manifest/i);
});

test("validate_stabilizer_fcpxml_import rejects DTD-invalid filter-video attributes", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-validator-dtd-attrs-test-"));
  const analysisPath = path.join(tmp, "analysis.json");
  const analysis = analysisResult();
  const cacheRoot = writeCachePayload(tmp, analysis);
  fs.writeFileSync(
    analysisPath,
    JSON.stringify({ status: "ok", cacheRoot, results: [analysis] }),
    "utf8"
  );
  const build = run("python3", [
    "scripts/build_stabilizer_fcpxml_import.py",
    "--source-fcpxml",
    fixture,
    "--analysis-json",
    analysisPath,
    "--output-dir",
    tmp,
    "--only-analyzed-assets",
    "--per-footage-packages",
  ]);
  const pkg = build.packages[0];
  const infoPath = path.join(pkg.outputPackage, "Info.fcpxml");
  const info = fs.readFileSync(infoPath, "utf8").replace(
    /<filter-video ref="/,
    '<filter-video nameOverride="Tokyo Walking Stabilizer" videoOverride="1" ref="'
  );
  fs.writeFileSync(infoPath, info, "utf8");
  const result = spawnSync("python3", [
    "scripts/validate_stabilizer_fcpxml_import.py",
    "--fcpxml",
    pkg.outputPackage,
    "--manifest",
    pkg.manifestPath,
    "--output",
    pkg.validationPath,
  ], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  assert.notEqual(result.status, 0);
  const validation = JSON.parse(result.stdout);
  assert.equal(validation.status, "fail");
  assert.equal(validation.importReady, false);
  assert.match(validation.failures.join("\n"), /DTD-invalid attribute/);
  assert.match(validation.failures.join("\n"), /nameOverride/);
  assert.match(validation.failures.join("\n"), /videoOverride/);
});
