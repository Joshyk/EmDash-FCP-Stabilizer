"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");
const test = require("node:test");

const {
  buildCacheRootFromAnalysis,
  cacheRootValue,
  defaultImportsDirForSource,
  failedRunResult,
  isFcpBundleSource,
  outputDirValue,
  parseAnalyzerProgressLine,
  processFailureDetails,
  processFailureMessage,
  readNativeAnalyzerCacheSchemaVersion,
} = require("../server.js");

test("buildCacheRootFromAnalysis requires analyzer-normalized cache root", () => {
  assert.equal(
    buildCacheRootFromAnalysis({ cacheRoot: "/tmp/imports/Analysis Files/TokyoWalkingStabilizerHostAnalysis" }),
    "/tmp/imports/Analysis Files/TokyoWalkingStabilizerHostAnalysis"
  );
  assert.throws(
    () => buildCacheRootFromAnalysis({}),
    /analyzer did not return a normalized cache root/
  );
});

test("defaultImportsDirForSource writes beside selected export in stablizer_analysis", () => {
  assert.equal(
    defaultImportsDirForSource("/Volumes/Edit/Project/Library.fcpbundle"),
    path.resolve("/Volumes/Edit/Project/stablizer_analysis")
  );
  assert.equal(
    defaultImportsDirForSource("/Volumes/Edit/Project/Event.fcpxmld"),
    path.resolve("/Volumes/Edit/Project/stablizer_analysis")
  );
  assert.equal(
    defaultImportsDirForSource("/Volumes/Edit/Project/Event.fcpxmld/Info.fcpxml"),
    path.resolve("/Volumes/Edit/Project/stablizer_analysis")
  );
  assert.equal(
    defaultImportsDirForSource("/Volumes/Edit/Project/Event.fcpxml"),
    path.resolve("/Volumes/Edit/Project/stablizer_analysis")
  );
});

test("fcpbundle sources force output and cache beside the bundle", () => {
  const sourcePath = "/Volumes/Edit/Project/Library.fcpbundle";
  const importsDir = path.resolve("/Volumes/Edit/Project/stablizer_analysis");
  assert.equal(isFcpBundleSource(sourcePath), true);
  assert.equal(
    outputDirValue("/Volumes/Edit/Project", sourcePath),
    importsDir
  );
  assert.equal(
    cacheRootValue("/tmp/other-cache", sourcePath, importsDir),
    importsDir
  );
});

test("xml sources still honor explicit output and cache roots", () => {
  const sourcePath = "/Volumes/Edit/Project/Event.fcpxmld";
  const importsDir = path.resolve("/tmp/custom-imports");
  assert.equal(isFcpBundleSource(sourcePath), false);
  assert.equal(outputDirValue(importsDir, sourcePath), importsDir);
  assert.equal(
    cacheRootValue("/tmp/custom-cache", sourcePath, importsDir),
    path.resolve("/tmp/custom-cache")
  );
});

test("readNativeAnalyzerCacheSchemaVersion exposes frontend writer schema", () => {
  const schemaVersion = readNativeAnalyzerCacheSchemaVersion();
  assert.equal(Number.isInteger(schemaVersion), true);
  assert.ok(schemaVersion >= 1);
});

test("parseAnalyzerProgressLine parses frame progress", () => {
  assert.deepEqual(
    parseAnalyzerProgressLine("progress P1000307: 7245/10501 frame(s) (69.0%, 79.8 fps)"),
    {
      kind: "frames",
      label: "P1000307",
      current: 7245,
      total: 10501,
      percent: 69.0,
      fps: 79.8,
      message: "progress P1000307: 7245/10501 frame(s) (69.0%, 79.8 fps)",
    }
  );
});

test("parseAnalyzerProgressLine parses submitted frame progress", () => {
  assert.deepEqual(
    parseAnalyzerProgressLine("progress P1000307: 0/10501 frame(s) complete, 16 submitted (0.2% submitted, 8.0 submit fps)"),
    {
      kind: "frames",
      label: "P1000307",
      current: 0,
      total: 10501,
      percent: 0,
      submitted: 16,
      submittedPercent: 0.2,
      submitFps: 8.0,
      message: "progress P1000307: 0/10501 frame(s) complete, 16 submitted (0.2% submitted, 8.0 submit fps)",
    }
  );
});

test("parseAnalyzerProgressLine parses chunk progress", () => {
  assert.deepEqual(
    parseAnalyzerProgressLine("progress P1000307: chunk 3/8 complete"),
    {
      kind: "chunks",
      label: "P1000307",
      current: 3,
      total: 8,
      message: "progress P1000307: chunk 3/8 complete",
    }
  );
});

test("parseAnalyzerProgressLine ignores non-progress output", () => {
  assert.equal(parseAnalyzerProgressLine("using Metal analyzer device: Apple M1"), null);
});

test("processFailureMessage reports JSON error output", () => {
  assert.equal(
    processFailureMessage(
      "python3",
      1,
      null,
      JSON.stringify({
        status: "error",
        error: "cache file is missing: /tmp/cache.json",
      }),
      ""
    ),
    "cache file is missing: /tmp/cache.json"
  );
});

test("processFailureDetails preserves analyzer JSON error payload", () => {
  const details = processFailureDetails(
    "python3",
    1,
    null,
    JSON.stringify({
      status: "error",
      error: "Metal analyzer device unavailable",
      schemaVersion: 1,
    }),
    ""
  );
  assert.equal(details.message, "Metal analyzer device unavailable");
  assert.equal(details.payload.status, "error");
  const result = failedRunResult(details);
  assert.equal(result.summary.fcpImportReady, false);
  assert.equal(result.summary.analyzedFailureCount, 1);
  assert.match(result.summary.failedClips[0].reason, /Metal analyzer device unavailable/);
  assert.equal(result.analyzerPayload.schemaVersion, 1);
});

test("processFailureMessage reports validation failures from stdout", () => {
  assert.equal(
    processFailureMessage(
      "python3",
      1,
      null,
      JSON.stringify({
        status: "fail",
        error: "validation failed",
        failures: ["Host Analysis Cache Identity does not match manifest", "cache payload frame count does not match manifest"],
      }),
      ""
    ),
    "validation failed: Host Analysis Cache Identity does not match manifest; cache payload frame count does not match manifest"
  );
});
