"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const { parseAnalyzerProgressLine } = require("../server.js");

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
