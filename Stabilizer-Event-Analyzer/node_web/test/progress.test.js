"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
  analysisBenchmarkPayload,
  analysisTimingBreakdown,
  buildCacheRootFromAnalysis,
  cacheRootValue,
  combineSourceSummaries,
  defaultImportsDirForSource,
  failedRunResult,
  isFcpBundleSource,
  normalizeSourceJobs,
  outputDirValue,
  parseAnalyzerProgressLine,
  processFailureDetails,
  processFailureMessage,
  readNativeAnalyzerCacheSchemaVersion,
  removeCompletedCheckpointWork,
  restorePackageInfoForPath,
  serialAnalysisWorkItems,
} = require("../server.js");

test("removeCompletedCheckpointWork removes only completed frontend checkpoint work", async () => {
  const importsDir = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-checkpoint-cleanup-"));
  const workDirectory = path.join(
    importsDir,
    "Library_fcpbundle",
    "Event-A",
    "TokyoWalkingStabilizerHostAnalysis",
    "analysis-work",
    "r2"
  );
  fs.mkdirSync(path.join(workDirectory, "checkpoint"), { recursive: true });
  fs.writeFileSync(path.join(workDirectory, "checkpoint", "checkpoint-manifest-v1.json"), "{}");

  const removed = await removeCompletedCheckpointWork({ workDirectories: [workDirectory] }, importsDir);

  assert.deepEqual(removed, [workDirectory]);
  assert.equal(fs.existsSync(workDirectory), false);
  assert.equal(fs.existsSync(path.dirname(path.dirname(workDirectory))), false);
});

test("analysisTimingBreakdown reports the measured bottleneck stage", () => {
  const breakdown = analysisTimingBreakdown({
    frameCount: 600,
    totalWallSeconds: 10,
    readFramesWallSeconds: 8,
    readerLaneWallSeconds: 14,
    decoderCopyNextFrameSeconds: 3,
    metalEncodeSeconds: 1.2,
    metalCompleteSeconds: 4.5,
    preparedPathSeconds: 0.8,
    cacheBuildSeconds: 0.1,
    cacheWriteSeconds: 0.4,
    readerLaneCount: 2,
    framesPerWallSecond: 60,
  });
  assert.equal(breakdown.bottleneck.key, "metalCompleteSeconds");
  assert.equal(breakdown.totalWallSeconds, 10);
  assert.equal(breakdown.readerLaneCount, 2);
});

test("analysisBenchmarkPayload preserves full-resolution analysis timing metadata", () => {
  const result = {
    assetId: "r2",
    name: "P1000307",
    footageFileName: "P1000307.mov",
    mediaKind: "original-media",
    sampleScalePercent: 100,
    sampleWidth: 5728,
    sampleHeight: 3024,
    frameCount: 10500,
    frameDurationSeconds: 1001 / 60000,
    rangeDurationSeconds: 175.175,
    cacheSchemaVersion: 32,
    cacheIdentity: "32:0:105105:1001:5728:3024:10500:aaa:bbb:ccc:end105105:P1000307",
    analysisTimings: {
      frameCount: 10500,
      totalWallSeconds: 120,
      readFramesWallSeconds: 90,
      readerLaneWallSeconds: 180,
      decoderCopyNextFrameSeconds: 22,
      metalEncodeSeconds: 12,
      metalCompleteSeconds: 50,
      preparedPathSeconds: 9,
      cacheBuildSeconds: 2,
      cacheWriteSeconds: 6,
      readerLaneCount: 4,
      framesPerWallSecond: 87.5,
    },
  };
  const payload = analysisBenchmarkPayload({
    sourcePath: "/tmp/Library.fcpbundle",
    sourceName: "Library.fcpbundle",
    sourceIndex: 1,
    totalSources: 1,
    analysisPath: "/tmp/job/analysis.json",
    analysis: { results: [result] },
  });
  assert.equal(payload.benchmarkType, "stabilizer-analysis-wall-clock");
  assert.equal(payload.results[0].sampleScalePercent, 100);
  assert.equal(payload.results[0].frameCount, 10500);
  assert.equal(payload.results[0].sampleWidth, 5728);
  assert.equal(payload.results[0].timingBreakdown.bottleneck.key, "metalCompleteSeconds");
});

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

test("restorePackageInfoForPath reads a per-clip restore package directory", async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-restore-package-"));
  const packageDir = path.join(tmp, "Library__Event__P1000307__schema32__sample100__10500f");
  const cacheDir = path.join(packageDir, "P1000307.analysis-cache");
  const cachesDir = path.join(cacheDir, "caches");
  fs.mkdirSync(cachesDir, { recursive: true });
  fs.mkdirSync(path.join(packageDir, "P1000307.fcpxmld"));
  const cacheFile = "host-analysis-v2-P1000307.json";
  fs.writeFileSync(path.join(cachesDir, cacheFile), JSON.stringify({ schemaVersion: 32, frames: [] }), "utf8");
  fs.writeFileSync(path.join(cacheDir, "host-analysis-index-v2.json"), JSON.stringify({ schemaVersion: 32, entries: [] }), "utf8");
  fs.writeFileSync(
    path.join(packageDir, "P1000307.analysis-manifest.json"),
    JSON.stringify({
      footageFileName: "P1000307.mov",
      footageName: "P1000307",
      eventName: "Event",
      eventRoot: "/Volumes/Edit/Library.fcpbundle/Event",
      mediaPath: "/Volumes/Edit/Library.fcpbundle/Event/Original Media/P1000307.mov",
      cacheSchemaVersion: 32,
      sampleScalePercent: 100,
      sampleWidth: 5728,
      sampleHeight: 3024,
      frameCount: 10500,
      cacheIdentity: "identity",
      cacheIdentityShort: "abc123ef",
      cachePayloadDirectory: "P1000307.analysis-cache",
      cachePayloadCacheFile: `P1000307.analysis-cache/caches/${cacheFile}`,
    }),
    "utf8"
  );
  const item = await restorePackageInfoForPath(packageDir);
  assert.equal(item.name, path.basename(packageDir));
  assert.equal(item.footageFileName, "P1000307.mov");
  assert.equal(item.eventName, "Event");
  assert.equal(item.cacheSchemaVersion, 32);
  assert.equal(item.cacheIdentityShort, "abc123ef");
  assert.equal(item.fcpxmldPath, path.join(packageDir, "P1000307.fcpxmld"));
  assert.equal(item.cachePayloadCacheFile, path.join(cachesDir, cacheFile));
  assert.deepEqual(item.warnings, []);
});

test("restorePackageInfoForPath rejects folders without one manifest", async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "stabilizer-restore-empty-"));
  await assert.rejects(
    () => restorePackageInfoForPath(tmp),
    /missing \*\.analysis-manifest\.json/
  );
});

test("defaultImportsDirForSource writes beside selected export in _walking_stabilizer_analysis", () => {
  assert.equal(
    defaultImportsDirForSource("/Volumes/Edit/Project/Library.fcpbundle"),
    path.resolve("/Volumes/Edit/Project/_walking_stabilizer_analysis/Library_fcpbundle")
  );
  assert.equal(
    defaultImportsDirForSource("/Volumes/Edit/Project/Event.fcpxmld"),
    path.resolve("/Volumes/Edit/Project/_walking_stabilizer_analysis")
  );
  assert.equal(
    defaultImportsDirForSource("/Volumes/Edit/Project/Event.fcpxmld/Info.fcpxml"),
    path.resolve("/Volumes/Edit/Project/_walking_stabilizer_analysis")
  );
  assert.equal(
    defaultImportsDirForSource("/Volumes/Edit/Project/Event.fcpxml"),
    path.resolve("/Volumes/Edit/Project/_walking_stabilizer_analysis")
  );
});

test("fcpbundle sources force output and cache beside the bundle", () => {
  const sourcePath = "/Volumes/Edit/Project/Library.fcpbundle";
  const importsDir = path.resolve("/Volumes/Edit/Project/_walking_stabilizer_analysis/Library_fcpbundle");
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

test("normalizeSourceJobs preserves legacy single source run bodies", () => {
  const jobs = normalizeSourceJobs({
    sourcePath: "/Volumes/Edit/Project/Event.fcpxmld",
    importsDir: "/tmp/imports",
    cacheRoot: "/tmp/cache",
    assetIds: ["r2"],
  });
  assert.equal(jobs.length, 1);
  assert.equal(jobs[0].sourcePath, path.resolve("/Volumes/Edit/Project/Event.fcpxmld"));
  assert.equal(jobs[0].importsDir, path.resolve("/tmp/imports"));
  assert.equal(jobs[0].cacheRoot, path.resolve("/tmp/cache"));
  assert.deepEqual(jobs[0].assetIds, ["r2"]);
});

test("normalizeSourceJobs merges duplicate source jobs and asset IDs", () => {
  const jobs = normalizeSourceJobs({
    sourceJobs: [
      {
        sourcePath: "/Volumes/Edit/Project/Event.fcpxmld",
        importsDir: "/tmp/imports",
        cacheRoot: "/tmp/cache",
        assetIds: ["r2", "r2", "r3"],
      },
      {
        sourcePath: "/Volumes/Edit/Project/Event.fcpxmld",
        importsDir: "/tmp/imports",
        cacheRoot: "/tmp/cache",
        assetIds: ["r3", "r4"],
      },
    ],
  });
  assert.equal(jobs.length, 1);
  assert.equal(jobs[0].sourcePath, path.resolve("/Volumes/Edit/Project/Event.fcpxmld"));
  assert.equal(jobs[0].importsDir, path.resolve("/tmp/imports"));
  assert.equal(jobs[0].cacheRoot, path.resolve("/tmp/cache"));
  assert.deepEqual(jobs[0].assetIds, ["r2", "r3", "r4"]);
});

test("normalizeSourceJobs rejects duplicate source jobs with conflicting roots", () => {
  assert.throws(
    () => normalizeSourceJobs({
      sourceJobs: [
        {
          sourcePath: "/Volumes/Edit/Project/Event.fcpxmld",
          importsDir: "/tmp/imports-a",
          cacheRoot: "/tmp/cache-a",
          assetIds: ["r2"],
        },
        {
          sourcePath: "/Volumes/Edit/Project/Event.fcpxmld",
          importsDir: "/tmp/imports-b",
          cacheRoot: "/tmp/cache-b",
          assetIds: ["r2"],
        },
      ],
    }),
    /duplicate sourcePath with conflicting output or cache roots/
  );
});

test("normalizeSourceJobs scopes roots per source and still forces fcpbundle outputs beside the bundle", () => {
  const jobs = normalizeSourceJobs({
    sourceJobs: [
      {
        sourcePath: "/Volumes/Edit/Project/Library.fcpbundle",
        importsDir: "/tmp/ignored-imports",
        cacheRoot: "/tmp/ignored-cache",
        assetIds: ["r2"],
      },
      {
        sourcePath: "/Volumes/Edit/Project/Event.fcpxmld",
        importsDir: "/tmp/custom-imports",
        cacheRoot: "/tmp/custom-cache",
        assetIds: ["r2"],
      },
    ],
  });
  assert.equal(jobs.length, 2);
  assert.equal(jobs[0].importsDir, path.resolve("/Volumes/Edit/Project/_walking_stabilizer_analysis/Library_fcpbundle"));
  assert.equal(jobs[0].cacheRoot, path.resolve("/Volumes/Edit/Project/_walking_stabilizer_analysis/Library_fcpbundle"));
  assert.equal(jobs[1].importsDir, path.resolve("/tmp/custom-imports"));
  assert.equal(jobs[1].cacheRoot, path.resolve("/tmp/custom-cache"));
});

test("serialAnalysisWorkItems turns each selected clip into an immediately publishable work item", () => {
  const sourceJobs = normalizeSourceJobs({
    sourceJobs: [
      {
        sourcePath: "/Volumes/Edit/Project/Library.fcpbundle",
        assetIds: ["r2", "r7"],
      },
      {
        sourcePath: "/Volumes/Edit/Project/Event.fcpxmld",
        importsDir: "/tmp/imports",
        cacheRoot: "/tmp/cache",
        assetIds: ["r9"],
      },
    ],
  });

  const workItems = serialAnalysisWorkItems(sourceJobs);

  assert.equal(workItems.length, 3);
  assert.deepEqual(workItems.map((item) => item.sourceJob.assetIds), [["r2"], ["r7"], ["r9"]]);
  assert.deepEqual(workItems.map((item) => item.sourceIndex), [0, 0, 1]);
  assert.deepEqual(workItems.map((item) => item.workIndex), [0, 1, 2]);
  assert.ok(workItems.every((item) => item.totalWorkItems === 3));
});

test("serialAnalysisWorkItems preserves analyze-all as one explicit work item", () => {
  const sourceJobs = normalizeSourceJobs({
    sourcePath: "/Volumes/Edit/Project/Event.fcpxmld",
    importsDir: "/tmp/imports",
    cacheRoot: "/tmp/cache",
    analyzeAll: true,
  });

  const workItems = serialAnalysisWorkItems(sourceJobs);

  assert.equal(workItems.length, 1);
  assert.equal(workItems[0].sourceJob.analyzeAll, true);
  assert.deepEqual(workItems[0].sourceJob.assetIds, []);
});

test("combineSourceSummaries keeps partial batch failures visible", () => {
  const summary = combineSourceSummaries([
    {
      status: "ok",
      sourceName: "Event A.fcpxmld",
      summary: {
        analyzedSuccessCount: 1,
        analyzedFailureCount: 0,
        packageCreatedCount: 1,
        validationPassCount: 1,
        validationFailCount: 0,
        eventCacheInstallPassCount: 1,
        eventCacheInstallFailCount: 0,
        fcpImportReady: true,
        failedClips: [],
        packages: [{
          sourceName: "Event A.fcpxmld",
          fcpxmldPath: "/tmp/Event A-stabilizer.fcpxmld",
          importReady: true,
        }],
      },
    },
    {
      status: "error",
      sourceName: "Event B.fcpxmld",
      summary: {
        analyzedSuccessCount: 0,
        analyzedFailureCount: 1,
        packageCreatedCount: 0,
        validationPassCount: 0,
        validationFailCount: 0,
        eventCacheInstallPassCount: 0,
        eventCacheInstallFailCount: 0,
        fcpImportReady: false,
        failedClips: [{ sourceName: "Event B.fcpxmld", reason: "native analyzer failed" }],
        packages: [],
      },
    },
  ]);
  assert.equal(summary.sourceSuccessCount, 1);
  assert.equal(summary.sourceFailureCount, 1);
  assert.equal(summary.packageCreatedCount, 1);
  assert.equal(summary.fcpImportReady, false);
  assert.equal(summary.failedClips[0].sourceName, "Event B.fcpxmld");
});

test("combineSourceSummaries counts multiple clip results from one source once", () => {
  const summary = combineSourceSummaries([
    {
      status: "ok",
      sourcePath: "/tmp/Event.fcpxmld",
      summary: { packages: [], failedClips: [] },
    },
    {
      status: "ok",
      sourcePath: "/tmp/Event.fcpxmld",
      summary: { packages: [], failedClips: [] },
    },
  ]);

  assert.equal(summary.sourceCount, 1);
  assert.equal(summary.sourceSuccessCount, 1);
  assert.equal(summary.sourceFailureCount, 0);
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
