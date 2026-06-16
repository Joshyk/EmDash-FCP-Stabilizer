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
          cacheIdentity: "15:0:6006:20:1920:1080:300:aaa:bbb:ccc:end6006:P1000307",
          cacheSchemaVersion: 15,
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
