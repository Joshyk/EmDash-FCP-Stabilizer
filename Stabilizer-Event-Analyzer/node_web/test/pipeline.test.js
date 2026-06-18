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
    cacheIdentity: `18:0:6006:20:1920:1080:300:aaa:bbb:ccc:end6006:${name}`,
    cacheSchemaVersion: 18,
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
          cacheSchemaVersion: 18,
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
          cacheSchemaVersion: 18,
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
          cacheSchemaVersion: 18,
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
          cacheSchemaVersion: 18,
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
  <library>
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
          cacheSchemaVersion: 18,
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
  assert.equal(payload.insertedFilters, 2);
  const info = fs.readFileSync(path.join(payload.outputPackage, "Info.fcpxml"), "utf8");
  assert.match(info, /Tokyo Walking Stabilizer - Analyzed Footage/);
  assert.match(info, /<asset[^>]+id="r2"[^>]+start="3600s"/);
  assert.equal((info.match(/<asset-clip[^>]+ref="r2"[^>]+start="3600s"/g) || []).length, 2);
  assert.doesNotMatch(info, /Large Existing Project/);
  assert.doesNotMatch(info, /Other/);
  assert.doesNotMatch(info, /Existing Effect/);
  assert.equal((info.match(/<filter-video[^>]+name="Tokyo Walking Stabilizer"/g) || []).length, 2);
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
  assert.match(path.basename(pkg.packageDirectory), /^P1000307__sample10__schema18__300f__/);
  assert.equal(path.basename(pkg.outputPackage), "P1000307.fcpxmld");
  assert.equal(path.basename(pkg.manifestPath), "P1000307.analysis-manifest.json");
  const manifest = JSON.parse(fs.readFileSync(pkg.manifestPath, "utf8"));
  assert.equal(manifest.footageFileName, "P1000307.mov");
  assert.equal(manifest.sourceMediaFingerprint, "aaa:bbb:ccc");
  assert.equal(manifest.cacheIdentity, analysisResult().cacheIdentity);
  assert.equal(manifest.preparedMotionPath, true);
  assert.equal(fs.existsSync(path.join(pkg.packageDirectory, manifest.cachePayloadCacheFile)), true);
  assert.equal(fs.existsSync(path.join(pkg.outputPackage, "Info.fcpxml")), true);
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
