"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { parseAnalyzerProgressLine, processFailureMessage } = require("../server.js");

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
