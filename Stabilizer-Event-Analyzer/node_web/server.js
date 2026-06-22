#!/usr/bin/env node
"use strict";

const fs = require("fs");
const fsp = require("fs/promises");
const http = require("http");
const os = require("os");
const path = require("path");
const { execFileSync, spawn } = require("child_process");
const packageInfo = require("./package.json");

const REPO_ROOT = path.resolve(__dirname, "..");
const WORKTREE_ROOT = path.resolve(REPO_ROOT, "..");
const WORKTREE_NAME = path.basename(path.dirname(WORKTREE_ROOT));
const GIT_COMMIT = shortGitCommit(WORKTREE_ROOT);
const PUBLIC_DIR = path.join(__dirname, "public");
const PYTHON = process.env.STABILIZER_PYTHON || "python3";
const HOST = process.env.STABILIZER_WEB_HOST || "127.0.0.1";
const PORT = Number(process.env.STABILIZER_WEB_PORT || 3091);
const OUTPUT_DIR = expandPath(process.env.STABILIZER_OUTPUT_DIR || path.join(REPO_ROOT, "xml", "fcpxml_imports"));
const CACHE_ROOT = expandPath(process.env.STABILIZER_CACHE_ROOT || "");
const JOB_DIR = path.join(REPO_ROOT, ".cache", "node_web_jobs");
const NATIVE_ANALYZER_SOURCE = path.join(REPO_ROOT, "native_analyzer", "Sources", "StabilizerEventAnalyzer", "main.swift");
const CACHE_SCHEMA_VERSION = readNativeAnalyzerCacheSchemaVersion();
const SAMPLE_SCALE_PERCENT_CHOICES = [100, 75, 50, 25, 10];
const DEFAULT_SAMPLE_SCALE_PERCENT = 100;
const DEFAULT_ANALYSIS_DIR_NAME = "stablizer_analysis";
const jobs = new Map();
let serverRef = null;

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
};

class CancelledError extends Error {
  constructor(message = "Stabilizer Event Analyzer job was cancelled.") {
    super(message);
    this.name = "CancelledError";
  }
}

class ProcessFailureError extends Error {
  constructor(message, payload = null) {
    super(message);
    this.name = "ProcessFailureError";
    this.payload = payload;
  }
}

function expandPath(value) {
  const text = String(value || "");
  if (!text) return "";
  if (text === "~") return os.homedir();
  if (text.startsWith("~/")) return path.join(os.homedir(), text.slice(2));
  return path.resolve(text);
}

function scriptPath(name) {
  return path.join(REPO_ROOT, "scripts", name);
}

function shortGitCommit(cwd) {
  try {
    return execFileSync("git", ["rev-parse", "--short", "HEAD"], {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}

function readNativeAnalyzerCacheSchemaVersion() {
  try {
    const source = fs.readFileSync(NATIVE_ANALYZER_SOURCE, "utf8");
    const match = /^\s*private\s+let\s+cacheSchemaVersion\s*=\s*(\d+)\s*$/m.exec(source);
    return match ? Number(match[1]) : null;
  } catch {
    return null;
  }
}

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload, null, 2);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "content-length": Buffer.byteLength(body),
  });
  res.end(body);
}

function sendError(res, status, message) {
  sendJson(res, status, { status: "error", error: message });
}

async function readJsonBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 2 * 1024 * 1024) {
      throw new Error("request body was larger than 2 MiB");
    }
    chunks.push(chunk);
  }
  const text = Buffer.concat(chunks).toString("utf8");
  return text ? JSON.parse(text) : {};
}

function updateJob(id, patch) {
  const existing = jobs.get(id) || { id, status: "queued", startedAt: Date.now(), updatedAt: Date.now() };
  if (existing.status === "cancelled" && patch.status !== "cancelled") {
    return existing;
  }
  const next = { ...existing, ...patch, updatedAt: Date.now() };
  jobs.set(id, next);
  return next;
}

function publicJob(job) {
  if (!job) return null;
  const live = job.status === "running" || job.status === "cancelling";
  const elapsedUntil = live ? Date.now() : (job.updatedAt || Date.now());
  return {
    id: job.id,
    status: job.status,
    stage: job.stage,
    message: job.message,
    startedAt: job.startedAt,
    updatedAt: job.updatedAt,
    elapsedSeconds: Math.max(0, Math.round((elapsedUntil - job.startedAt) / 1000)),
    cancellable: job.status === "running" || job.status === "cancelling",
    cacheSchemaVersion: job.cacheSchemaVersion || CACHE_SCHEMA_VERSION,
    progress: job.progress,
    result: job.result,
    error: job.error,
  };
}

function latestPublicJob() {
  const allJobs = Array.from(jobs.values());
  if (!allJobs.length) return null;
  const activeJobs = allJobs.filter((job) => job.status === "running" || job.status === "cancelling");
  const candidates = activeJobs.length ? activeJobs : allJobs;
  candidates.sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
  return publicJob(candidates[0]);
}

function jobId() {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

function assertNotCancelled(jobIdValue) {
  const job = jobs.get(jobIdValue);
  if (job && job.cancelRequested) {
    throw new CancelledError();
  }
}

function signalProcessGroup(child, signal) {
  if (!child || !child.pid) return null;
  try {
    process.kill(-child.pid, signal);
    return null;
  } catch (groupError) {
    try {
      child.kill(signal);
      return null;
    } catch {
      return groupError.code === "ESRCH" ? null : groupError;
    }
  }
}

function terminateJobProcess(id, child) {
  if (!child || !child.pid || child.exitCode !== null || child.killed) return null;
  const signalError = signalProcessGroup(child, "SIGTERM");
  if (signalError) {
    updateJob(id, {
      error: `Failed to signal analyzer process group: ${signalError.message}`,
      message: `Failed to signal analyzer process group: ${signalError.message}`,
    });
    return null;
  }
  return setTimeout(() => {
    const job = jobs.get(id);
    if (job && job.currentProcess === child) {
      const killError = signalProcessGroup(child, "SIGKILL");
      if (killError) {
        updateJob(id, {
          error: `Failed to force-kill analyzer process group: ${killError.message}`,
          message: `Failed to force-kill analyzer process group: ${killError.message}`,
        });
      }
    }
  }, 3000);
}

function processFailureDetails(command, code, signal, stdout, stderr) {
  const stderrText = String(stderr || "").trim();
  if (stderrText) return { message: stderrText, payload: null };

  const stdoutText = String(stdout || "").trim();
  if (stdoutText) {
    try {
      const payload = JSON.parse(stdoutText);
      const failures = Array.isArray(payload.failures)
        ? payload.failures.filter(Boolean)
        : [];
      if (payload.error && failures.length) {
        return { message: `${payload.error}: ${failures.join("; ")}`, payload };
      }
      if (payload.error) return { message: String(payload.error), payload };
      if (failures.length) return { message: failures.join("; "), payload };
      if (payload.status && payload.status !== "ok") {
        return { message: `${command} exited with ${code}; JSON status: ${payload.status}`, payload };
      }
    } catch {
      return { message: stdoutText.slice(0, 2000), payload: null };
    }
  }

  return { message: `${command} exited with ${code}${signal ? ` (${signal})` : ""}`, payload: null };
}

function processFailureMessage(command, code, signal, stdout, stderr) {
  return processFailureDetails(command, code, signal, stdout, stderr).message;
}

function failedRunResult(error) {
  const reason = error && error.message ? error.message : "analysis failed";
  return {
    status: "error",
    summary: {
      analyzedSuccessCount: 0,
      analyzedFailureCount: 1,
      packageCreatedCount: 0,
      validationPassCount: 0,
      validationFailCount: 0,
      fcpImportReady: false,
      failedClips: [{ reason }],
      packages: [],
    },
    error: reason,
    analyzerPayload: error && error.payload ? error.payload : undefined,
  };
}

function runJsonProcess(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    let child;
    let stdout = "";
    let stderr = "";
    try {
      child = spawn(command, args, {
        cwd: REPO_ROOT,
        stdio: ["ignore", "pipe", "pipe"],
        env: { ...process.env, PYTHONUNBUFFERED: "1" },
        detached: true,
      });
    } catch (error) {
      reject(error);
      return;
    }
    if (options.jobId) {
      updateJob(options.jobId, { currentProcess: child });
      const job = jobs.get(options.jobId);
      if (job && job.cancelRequested) {
        const killTimer = terminateJobProcess(options.jobId, child);
        updateJob(options.jobId, { killTimer });
      }
    }
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      stderr += text;
      if (options.onStderr) {
        options.onStderr(text);
      }
    });
    child.on("error", reject);
    child.on("close", (code, signal) => {
      let wasCancelled = false;
      if (options.jobId) {
        const job = jobs.get(options.jobId);
        wasCancelled = Boolean(job && job.cancelRequested);
        if (job && job.killTimer) {
          clearTimeout(job.killTimer);
        }
        if (job && job.currentProcess === child) {
          updateJob(options.jobId, { currentProcess: null, killTimer: null });
        }
      }
      if (wasCancelled) {
        reject(new CancelledError());
        return;
      }
      if (code !== 0) {
        const details = processFailureDetails(command, code, signal, stdout, stderr);
        reject(new ProcessFailureError(details.message, details.payload));
        return;
      }
      try {
        resolve(JSON.parse(stdout));
      } catch (error) {
        reject(new Error(`invalid JSON from ${command}: ${stdout.slice(0, 500)}`));
      }
    });
  });
}

function progressLineHandler(jobIdValue) {
  let pending = "";
  const applyLine = (line) => {
    const parsedProgress = parseAnalyzerProgressLine(line);
    if (parsedProgress) {
      updateJob(jobIdValue, {
        stage: "analyzing",
        progress: parsedProgress,
      });
      return;
    }
    updateJob(jobIdValue, {
      stage: "analyzing",
      message: line,
    });
  };
  return (text) => {
    const parts = (pending + text).split(/[\r\n]+/);
    pending = parts.pop() || "";
    const lines = parts.map((line) => line.trim()).filter(Boolean);
    for (const line of lines) {
      applyLine(line);
    }
    const pendingProgress = parseAnalyzerProgressLine(pending.trim());
    if (pendingProgress) {
      updateJob(jobIdValue, {
        stage: "analyzing",
        progress: pendingProgress,
      });
      pending = "";
    }
  };
}

function parseAnalyzerProgressLine(line) {
  const submittedFrameMatch = /^progress\s+(.+?):\s+(\d+)\/(\d+)\s+frame\(s\)\s+complete,\s+(\d+)\s+submitted\s+\(([\d.]+)%\s+submitted,\s+([\d.]+)\s+submit fps\)$/.exec(line);
  if (submittedFrameMatch) {
    return {
      kind: "frames",
      label: submittedFrameMatch[1],
      current: Number(submittedFrameMatch[2]),
      total: Number(submittedFrameMatch[3]),
      percent: Number(submittedFrameMatch[2]) / Math.max(1, Number(submittedFrameMatch[3])) * 100,
      submitted: Number(submittedFrameMatch[4]),
      submittedPercent: Number(submittedFrameMatch[5]),
      submitFps: Number(submittedFrameMatch[6]),
      message: line,
    };
  }
  const frameMatch = /^progress\s+(.+?):\s+(\d+)\/(\d+)\s+frame\(s\)\s+\(([\d.]+)%,\s+([\d.]+)\s+fps\)$/.exec(line);
  if (frameMatch) {
    return {
      kind: "frames",
      label: frameMatch[1],
      current: Number(frameMatch[2]),
      total: Number(frameMatch[3]),
      percent: Number(frameMatch[4]),
      fps: Number(frameMatch[5]),
      message: line,
    };
  }
  const chunkMatch = /^progress\s+(.+?):\s+chunk\s+(\d+)\/(\d+)\s+complete$/.exec(line);
  if (chunkMatch) {
    return {
      kind: "chunks",
      label: chunkMatch[1],
      current: Number(chunkMatch[2]),
      total: Number(chunkMatch[3]),
      message: line,
    };
  }
  return null;
}

async function ensureDirs() {
  await fsp.mkdir(OUTPUT_DIR, { recursive: true });
  await fsp.mkdir(JOB_DIR, { recursive: true });
}

function defaultImportsDirForSource(sourcePath) {
  const resolved = expandPath(sourcePath);
  if (!resolved) return "";
  if (path.basename(resolved) === "Info.fcpxml" && path.basename(path.dirname(resolved)).endsWith(".fcpxmld")) {
    return path.join(path.dirname(path.dirname(resolved)), DEFAULT_ANALYSIS_DIR_NAME);
  }
  return path.join(path.dirname(resolved), DEFAULT_ANALYSIS_DIR_NAME);
}

function runTextProcess(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: REPO_ROOT,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk.toString(); });
    child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        const error = new Error(stderr.trim() || `${command} exited with ${code}`);
        error.code = code;
        error.stderr = stderr;
        reject(error);
        return;
      }
      resolve(stdout);
    });
  });
}

async function exportItemForPath(selectedPath) {
  const resolved = expandPath(selectedPath);
  const stat = await fsp.stat(resolved);
  const name = path.basename(resolved);
  if (stat.isDirectory() && name.endsWith(".fcpxmld")) {
    return { name, path: resolved, importsDir: defaultImportsDirForSource(resolved), mtimeMs: stat.mtimeMs, kind: "fcpxmld" };
  }
  if (stat.isDirectory() && name.endsWith(".fcpbundle")) {
    return { name, path: resolved, importsDir: defaultImportsDirForSource(resolved), mtimeMs: stat.mtimeMs, kind: "fcpbundle" };
  }
  if (stat.isFile() && name.endsWith(".fcpxml")) {
    return { name, path: resolved, importsDir: defaultImportsDirForSource(resolved), mtimeMs: stat.mtimeMs, kind: "fcpxml" };
  }
  throw new Error(`${selectedPath} is not an FCP library, FCPXMLD package, or .fcpxml file`);
}

async function selectExportFiles() {
  const script = [
    'set selectedFiles to choose file with prompt "Select FCP libraries, FCPXMLD packages, or Info.fcpxml files" with multiple selections allowed',
    "set outputPaths to {}",
    "repeat with selectedFile in selectedFiles",
    "  set end of outputPaths to POSIX path of selectedFile",
    "end repeat",
    "set AppleScript's text item delimiters to linefeed",
    "return outputPaths as text",
  ].join("\n");
  let stdout = "";
  try {
    stdout = await runTextProcess("osascript", ["-e", script]);
  } catch (error) {
    if (String(error.stderr || error.message).includes("-128")) {
      return { items: [], rejected: [] };
    }
    throw error;
  }
  const paths = stdout.split(/\r?\n/).map((item) => item.trim()).filter(Boolean);
  const items = [];
  const rejected = [];
  for (const selectedPath of paths) {
    try {
      items.push(await exportItemForPath(selectedPath));
    } catch (error) {
      rejected.push({ path: selectedPath, reason: error.message });
    }
  }
  return { items, rejected };
}

async function cacheRootItemForPath(selectedPath) {
  const resolved = expandPath(selectedPath);
  const stat = await fsp.stat(resolved);
  if (!stat.isDirectory()) {
    throw new Error(`${selectedPath} is not a directory`);
  }
  const name = path.basename(resolved);
  let kind = "event-folder";
  if (name === "TokyoWalkingStabilizerHostAnalysis") {
    kind = "cache-root";
  } else if (name === "Analysis Files") {
    kind = "analysis-files";
  }
  return { name, path: resolved, kind };
}

async function selectCacheRoot() {
  const script = [
    'set selectedFolder to choose folder with prompt "Select Imports folder"',
    "return POSIX path of selectedFolder",
  ].join("\n");
  let stdout = "";
  try {
    stdout = await runTextProcess("osascript", ["-e", script]);
  } catch (error) {
    if (String(error.stderr || error.message).includes("-128")) {
      return { item: null };
    }
    throw error;
  }
  const selectedPath = stdout.trim();
  if (!selectedPath) {
    return { item: null };
  }
  return { item: await cacheRootItemForPath(selectedPath) };
}

async function listAssets(sourcePath) {
  const resolved = expandPath(sourcePath);
  if (!resolved) throw new Error("sourcePath is required");
  return runJsonProcess(PYTHON, [scriptPath("list_event_assets.py"), "--fcpxml", resolved]);
}

function selectedAssetArgs(assetIds, analyzeAll) {
  if (analyzeAll) return ["--all"];
  const ids = Array.isArray(assetIds) ? assetIds.filter(Boolean) : [];
  if (!ids.length) throw new Error("select at least one asset");
  return ids.flatMap((id) => ["--asset-id", String(id)]);
}

function cacheRootValue(value) {
  const resolved = expandPath(value || CACHE_ROOT);
  if (!resolved) throw new Error("cache root is required");
  return resolved;
}

function buildCacheRootFromAnalysis(analysis) {
  if (!analysis || !analysis.cacheRoot) {
    throw new Error("analyzer did not return a normalized cache root");
  }
  return analysis.cacheRoot;
}

function outputDirValue(value, sourcePath) {
  const resolved = expandPath(value || defaultImportsDirForSource(sourcePath) || OUTPUT_DIR);
  if (!resolved) throw new Error("imports directory is required");
  return resolved;
}

async function runAnalyzer(body, progress, forcedJobId) {
  const id = forcedJobId || jobId();
  const dir = path.join(JOB_DIR, id);
  await fsp.mkdir(dir, { recursive: true });
  const sourcePath = expandPath(body.sourcePath);
  const importsDir = outputDirValue(body.importsDir || body.outputDir, sourcePath);
  const cacheRoot = cacheRootValue(body.cacheRoot || importsDir);
  const sampleScalePercent = Number(body.sampleScalePercent || DEFAULT_SAMPLE_SCALE_PERCENT);
  if (!SAMPLE_SCALE_PERCENT_CHOICES.includes(sampleScalePercent)) {
    throw new Error(`sampleScalePercent must be one of ${SAMPLE_SCALE_PERCENT_CHOICES.join(", ")}`);
  }

  progress("analyzing", "Running serial Event media analysis.");
  assertNotCancelled(id);
  const analysisArgs = [
    scriptPath("analyze_event_assets.py"),
    "--fcpxml",
    sourcePath,
    "--cache-root",
    cacheRoot,
    "--sample-scale-percent",
    String(sampleScalePercent),
    ...selectedAssetArgs(body.assetIds, body.analyzeAll === true),
    "--progress",
  ];
  const analysis = await runJsonProcess(PYTHON, analysisArgs, { jobId: id, onStderr: progressLineHandler(id) });
  const analysisPath = path.join(dir, "analysis.json");
  await fsp.writeFile(analysisPath, JSON.stringify(analysis, null, 2), "utf8");
  const analysisCacheRoot = buildCacheRootFromAnalysis(analysis);

  progress("building", "Building analyzed-footage-only Stabilizer FCPXMLD import package.");
  assertNotCancelled(id);
  const build = await runJsonProcess(PYTHON, [
    scriptPath("build_stabilizer_fcpxml_import.py"),
    "--source-fcpxml",
    sourcePath,
    "--analysis-json",
    analysisPath,
    "--output-dir",
    importsDir,
    "--cache-root",
    analysisCacheRoot,
    "--only-analyzed-assets",
    "--per-footage-packages",
  ], { jobId: id });

  progress("validating", "Validating Stabilizer FCPXMLD package(s) before FCP import.");
  assertNotCancelled(id);
  const packages = Array.isArray(build.packages) ? build.packages : [];
  const validations = [];
  for (const pkg of packages) {
    try {
      const validation = await runJsonProcess(PYTHON, [
        scriptPath("validate_stabilizer_fcpxml_import.py"),
        "--fcpxml",
        pkg.outputPackage,
        "--manifest",
        pkg.manifestPath,
        "--output",
        pkg.validationPath,
      ], { jobId: id });
      validations.push({ ...validation, packageDirectory: pkg.packageDirectory, outputPackage: pkg.outputPackage });
    } catch (error) {
      let validationPayload = null;
      try {
        validationPayload = JSON.parse(await fsp.readFile(pkg.validationPath, "utf8"));
      } catch {
        validationPayload = { status: "fail", failures: [error.message], importReady: false };
        await fsp.writeFile(pkg.validationPath, JSON.stringify(validationPayload, null, 2), "utf8");
      }
      validations.push({ ...validationPayload, packageDirectory: pkg.packageDirectory, outputPackage: pkg.outputPackage });
    }
  }
  const validationFailures = validations.filter((item) => item.status !== "pass" || item.importReady !== true);
  if (validationFailures.length) {
    const firstFailure = validationFailures[0];
    const reason = (firstFailure.failures || [firstFailure.error || "validation failed"])[0];
    const error = new Error(`FCPXMLD validation failed for ${path.basename(firstFailure.packageDirectory || firstFailure.outputPackage || "package")}: ${reason}`);
    error.validations = validations;
    throw error;
  }

  progress("installing-cache", "Installing package cache payload(s) into source Event cache root.");
  assertNotCancelled(id);
  const eventCacheInstallations = [];
  for (const pkg of packages) {
    try {
      const installation = await runJsonProcess(PYTHON, [
        scriptPath("install_stabilizer_package_cache.py"),
        "--manifest",
        pkg.manifestPath,
      ], { jobId: id });
      eventCacheInstallations.push({ ...installation, packageDirectory: pkg.packageDirectory, outputPackage: pkg.outputPackage });
    } catch (error) {
      eventCacheInstallations.push({
        status: "error",
        error: error.message,
        packageDirectory: pkg.packageDirectory,
        outputPackage: pkg.outputPackage,
      });
    }
  }
  const installFailures = eventCacheInstallations.filter((item) => item.status !== "ok");
  if (installFailures.length) {
    const firstFailure = installFailures[0];
    const error = new Error(`Event cache install failed for ${path.basename(firstFailure.packageDirectory || firstFailure.outputPackage || "package")}: ${firstFailure.error || "install failed"}`);
    error.eventCacheInstallations = eventCacheInstallations;
    throw error;
  }

  const summary = batchSummary(analysis, build, validations, eventCacheInstallations);

  return {
    status: "ok",
    jobId: id,
    cacheSchemaVersion: CACHE_SCHEMA_VERSION,
    sourcePath,
    cacheRoot: analysisCacheRoot,
    importsDir,
    analysisPath,
    resultCount: (analysis.results || []).length,
    results: analysis.results || [],
    skipped: analysis.skipped || [],
    packages,
    validations,
    eventCacheInstallations,
    summary,
    outputPackage: build.outputPackage,
    outputPackages: packages.map((pkg) => pkg.outputPackage),
    insertedFilters: build.insertedFilters,
    removedExistingFilters: build.removedExistingFilters,
    onlyAnalyzedAssets: build.onlyAnalyzedAssets === true,
    perFootagePackages: build.perFootagePackages === true,
  };
}

function batchSummary(analysis, build, validations, eventCacheInstallations = []) {
  const results = Array.isArray(analysis.results) ? analysis.results : [];
  const skipped = Array.isArray(analysis.skipped) ? analysis.skipped : [];
  const packages = Array.isArray(build.packages) ? build.packages : [];
  const validationPass = validations.filter((item) => item.status === "pass" && item.importReady === true).length;
  const validationFail = Math.max(0, validations.length - validationPass);
  const eventCacheInstallPass = eventCacheInstallations.filter((item) => item.status === "ok").length;
  const eventCacheInstallFail = Math.max(0, eventCacheInstallations.length - eventCacheInstallPass);
  return {
    analyzedSuccessCount: results.length,
    analyzedFailureCount: skipped.length,
    packageCreatedCount: packages.length,
    validationPassCount: validationPass,
    validationFailCount: validationFail,
    eventCacheInstallPassCount: eventCacheInstallPass,
    eventCacheInstallFailCount: eventCacheInstallFail,
    fcpImportReady: packages.length > 0
      && validationFail === 0
      && validationPass === packages.length
      && eventCacheInstallFail === 0
      && eventCacheInstallPass === packages.length,
    failedClips: [
      ...skipped.map((reason) => ({ reason })),
      ...validations
        .filter((item) => item.status !== "pass" || item.importReady !== true)
        .map((item) => ({
          packagePath: item.packageDirectory || item.outputPackage,
          reason: (item.failures || [item.error || "validation failed"])[0],
        })),
      ...eventCacheInstallations
        .filter((item) => item.status !== "ok")
        .map((item) => ({
          packagePath: item.packageDirectory || item.outputPackage,
          reason: item.error || "Event cache install failed",
        })),
    ],
    packages: packages.map((pkg) => {
      const installation = eventCacheInstallations.find((item) => item.outputPackage === pkg.outputPackage);
      const validationReady = validations.some((item) => item.outputPackage === pkg.outputPackage && item.importReady === true);
      const eventCacheInstalled = installation ? installation.status === "ok" : false;
      return {
        packagePath: pkg.packageDirectory,
        fcpxmldPath: pkg.outputPackage,
        sampleScalePercent: pkg.sampleScalePercent,
        sampleWidth: pkg.sampleWidth,
        sampleHeight: pkg.sampleHeight,
        cacheSchemaVersion: pkg.cacheSchemaVersion,
        cacheIdentityShort: pkg.cacheIdentityShort,
        eventCacheInstalled,
        eventCacheRoot: installation && installation.cacheRoot,
        importReady: validationReady && eventCacheInstalled,
      };
    }),
  };
}

function startRunJob(body) {
  const id = jobId();
  updateJob(id, {
    status: "running",
    stage: "queued",
    message: "Queued Stabilizer Event analysis.",
    cacheSchemaVersion: CACHE_SCHEMA_VERSION,
  });
  setImmediate(async () => {
    try {
      const result = await runAnalyzer(body, (stage, message, patch = {}) => {
        updateJob(id, { stage, message, ...patch });
      }, id);
      updateJob(id, { status: "done", stage: "done", message: "Analysis complete.", result });
    } catch (error) {
      if (error instanceof CancelledError) {
        updateJob(id, { status: "cancelled", stage: "cancelled", message: error.message });
      } else {
        updateJob(id, {
          status: "error",
          stage: "error",
          message: error.message,
          error: error.message,
          result: failedRunResult(error),
        });
      }
    }
  });
  return publicJob(jobs.get(id));
}

function cancelJob(id) {
  const job = jobs.get(id);
  if (!job) throw new Error("job was not found");
  if (job.status === "done" || job.status === "error" || job.status === "cancelled") {
    return publicJob(job);
  }
  updateJob(id, { status: "cancelling", cancelRequested: true, message: "Cancelling job." });
  if (job.currentProcess) {
    const killTimer = terminateJobProcess(id, job.currentProcess);
    updateJob(id, {
      killTimer,
      message: killTimer
        ? "Cancelling job; sent SIGTERM to analyzer process group."
        : "Cancelling job; analyzer process already exited.",
    });
  }
  return publicJob(jobs.get(id));
}

function revealPath(targetPath) {
  return new Promise((resolve) => {
    const child = spawn("open", ["-R", expandPath(targetPath)], { stdio: ["ignore", "ignore", "pipe"] });
    let stderr = "";
    child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
    child.on("close", (code) => resolve({ code, stderr }));
  });
}

function openPath(targetPath) {
  return new Promise((resolve) => {
    const child = spawn("open", [expandPath(targetPath)], { stdio: ["ignore", "ignore", "pipe"] });
    let stderr = "";
    child.stderr.on("data", (chunk) => { stderr += chunk.toString(); });
    child.on("close", (code) => resolve({ code, stderr }));
  });
}

async function handleApi(req, res, pathname) {
  try {
    if (req.method === "GET" && pathname === "/api/config") {
      return sendJson(res, 200, {
        status: "ok",
        appVersion: packageInfo.version,
        gitCommit: GIT_COMMIT,
        worktreeName: WORKTREE_NAME,
        repoRoot: REPO_ROOT,
        outputDir: OUTPUT_DIR,
        defaultImportsDir: "",
        defaultAnalysisDirName: DEFAULT_ANALYSIS_DIR_NAME,
        cacheRoot: CACHE_ROOT,
        cacheSchemaVersion: CACHE_SCHEMA_VERSION,
        sampleScalePercentChoices: SAMPLE_SCALE_PERCENT_CHOICES,
        defaultSampleScalePercent: DEFAULT_SAMPLE_SCALE_PERCENT,
        python: PYTHON,
      });
    }
    if (req.method === "POST" && pathname === "/api/select-exports") {
      return sendJson(res, 200, { status: "ok", ...(await selectExportFiles()) });
    }
    if (req.method === "POST" && pathname === "/api/select-cache-root") {
      return sendJson(res, 200, { status: "ok", ...(await selectCacheRoot()) });
    }
    if (req.method === "POST" && pathname === "/api/assets") {
      const body = await readJsonBody(req);
      return sendJson(res, 200, await listAssets(body.sourcePath));
    }
    if (req.method === "POST" && pathname === "/api/run") {
      const body = await readJsonBody(req);
      return sendJson(res, 200, { status: "ok", job: startRunJob(body) });
    }
    if (req.method === "GET" && pathname === "/api/job") {
      const url = new URL(req.url || "/", `http://${HOST}:${PORT}`);
      const job = publicJob(jobs.get(url.searchParams.get("id")));
      if (!job) return sendError(res, 404, "job was not found");
      return sendJson(res, 200, { status: "ok", job });
    }
    if (req.method === "GET" && pathname === "/api/latest-job") {
      return sendJson(res, 200, { status: "ok", job: latestPublicJob() });
    }
    if (req.method === "POST" && pathname === "/api/cancel") {
      const body = await readJsonBody(req);
      return sendJson(res, 200, { status: "ok", job: cancelJob(body.id) });
    }
    if (req.method === "POST" && pathname === "/api/reveal") {
      const body = await readJsonBody(req);
      const result = await revealPath(body.path);
      return sendJson(res, result.code === 0 ? 200 : 500, { status: result.code === 0 ? "ok" : "error", stderr: result.stderr });
    }
    if (req.method === "POST" && pathname === "/api/open") {
      const body = await readJsonBody(req);
      const result = await openPath(body.path);
      return sendJson(res, result.code === 0 ? 200 : 500, { status: result.code === 0 ? "ok" : "error", stderr: result.stderr });
    }
    if (req.method === "POST" && pathname === "/api/shutdown") {
      sendJson(res, 200, { status: "ok" });
      setTimeout(() => serverRef && serverRef.close(() => process.exit(0)), 50);
      return;
    }
    return sendError(res, 404, "API route was not found");
  } catch (error) {
    return sendError(res, 500, error.message);
  }
}

async function serveStatic(req, res, pathname) {
  if (pathname === "/version.js") {
    const body = `window.STABILIZER_EVENT_ANALYZER_VERSION=${JSON.stringify(packageInfo.version)};\n`;
    res.writeHead(200, {
      "content-type": "application/javascript; charset=utf-8",
      "cache-control": "no-store",
    });
    res.end(body);
    return;
  }
  const relative = pathname === "/" ? "/index.html" : decodeURIComponent(pathname);
  const targetPath = path.normalize(path.join(PUBLIC_DIR, relative));
  if (!targetPath.startsWith(PUBLIC_DIR)) {
    return sendError(res, 403, "forbidden");
  }
  try {
    const data = await fsp.readFile(targetPath);
    if (path.basename(targetPath) === "index.html") {
      const assetVersion = encodeURIComponent(GIT_COMMIT || packageInfo.version || "dev");
      const body = data.toString("utf8").replaceAll("__ASSET_VERSION__", assetVersion);
      res.writeHead(200, {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "no-store",
      });
      res.end(body);
      return;
    }
    res.writeHead(200, {
      "content-type": MIME_TYPES[path.extname(targetPath)] || "application/octet-stream",
      "cache-control": "no-store",
    });
    res.end(data);
  } catch {
    sendError(res, 404, "not found");
  }
}

async function main() {
  await ensureDirs();
  serverRef = http.createServer(async (req, res) => {
    const url = new URL(req.url || "/", `http://${HOST}:${PORT}`);
    if (url.pathname.startsWith("/api/")) {
      return handleApi(req, res, url.pathname);
    }
    return serveStatic(req, res, url.pathname);
  });
  serverRef.listen(PORT, HOST, () => {
    console.log(`Stabilizer Event Analyzer listening on http://${HOST}:${PORT}`);
  });
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack || error.message);
    process.exit(1);
  });
}

module.exports = {
  buildCacheRootFromAnalysis,
  defaultImportsDirForSource,
  failedRunResult,
  parseAnalyzerProgressLine,
  processFailureDetails,
  processFailureMessage,
  readNativeAnalyzerCacheSchemaVersion,
};
