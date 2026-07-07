"use strict";

const LAST_ANALYSIS_STORAGE_KEY = "tokyoWalkingStabilizer.eventAnalyzer.lastAnalysis.v2";
const LEGACY_LAST_ANALYSIS_STORAGE_KEY = "tokyoWalkingStabilizer.eventAnalyzer.lastAnalysis.v1";
const DEFAULT_ANALYSIS_DIR_NAME = "_walking_stabilizer_analysis";
const HIDDEN_CLIP_NAME_TOKEN = "(fcp1)";

const state = {
  config: null,
  activeSourcePath: "",
  sources: [],
  assets: [],
  selectedClipKeys: new Set(),
  pendingPresetClipKeys: null,
  importsOverride: "",
  currentJobId: "",
  lastResult: null,
  restorePackage: null,
  restoreInstallation: null,
};

const el = {
  configText: document.getElementById("configText"),
  versionText: document.getElementById("versionText"),
  selectExportFilesButton: document.getElementById("selectExportFilesButton"),
  lastAnalysisButton: document.getElementById("lastAnalysisButton"),
  exportsList: document.getElementById("exportsList"),
  sourcePathInput: document.getElementById("sourcePathInput"),
  loadAssetsButton: document.getElementById("loadAssetsButton"),
  selectAllButton: document.getElementById("selectAllButton"),
  clearSelectionButton: document.getElementById("clearSelectionButton"),
  sourceText: document.getElementById("sourceText"),
  assetsBody: document.getElementById("assetsBody"),
  selectedText: document.getElementById("selectedText"),
  cacheRootInput: document.getElementById("cacheRootInput"),
  selectCacheRootButton: document.getElementById("selectCacheRootButton"),
  sampleScaleInput: document.getElementById("sampleScaleInput"),
  runButton: document.getElementById("runButton"),
  cancelButton: document.getElementById("cancelButton"),
  statusBox: document.getElementById("statusBox"),
  batchSummary: document.getElementById("batchSummary"),
  resultActions: document.getElementById("resultActions"),
  revealCacheButton: document.getElementById("revealCacheButton"),
  revealImportButton: document.getElementById("revealImportButton"),
  openImportButton: document.getElementById("openImportButton"),
  restorePackagePathInput: document.getElementById("restorePackagePathInput"),
  selectRestorePackageButton: document.getElementById("selectRestorePackageButton"),
  loadRestorePackageButton: document.getElementById("loadRestorePackageButton"),
  installRestorePackageButton: document.getElementById("installRestorePackageButton"),
  restoreSummary: document.getElementById("restoreSummary"),
  restoreStatusBox: document.getElementById("restoreStatusBox"),
  revealRestorePackageButton: document.getElementById("revealRestorePackageButton"),
  revealInstalledCacheButton: document.getElementById("revealInstalledCacheButton"),
  openRestoreImportButton: document.getElementById("openRestoreImportButton"),
};

function renderAppVersion(version, config = {}) {
  const parts = [];
  if (version) parts.push(`v${version}`);
  if (config.cacheSchemaVersion) parts.push(`schema ${config.cacheSchemaVersion}`);
  if (config.gitCommit) parts.push(config.gitCommit);
  if (config.worktreeName) parts.push(config.worktreeName);
  el.versionText.textContent = parts.join(" / ");
}

renderAppVersion(window.STABILIZER_EVENT_ANALYZER_VERSION);

async function api(path, options = {}) {
  const response = await fetch(path, {
    method: options.method || "GET",
    cache: "no-store",
    headers: { "content-type": "application/json" },
    body: options.body ? JSON.stringify(options.body) : undefined,
  });
  const payload = await response.json();
  if (!response.ok || payload.status === "error") {
    throw new Error(payload.error || `HTTP ${response.status}`);
  }
  return payload;
}

function setStatus(message, kind = "") {
  el.statusBox.className = `status-box ${kind}`.trim();
  el.statusBox.textContent = message;
}

function setRestoreStatus(message, kind = "") {
  el.restoreStatusBox.className = `status-box compact-status ${kind}`.trim();
  el.restoreStatusBox.textContent = message;
}

function formatProgress(progress) {
  if (!progress) return "";
  if (progress.kind === "frames") {
    const label = progress.label || "analysis";
    const current = Number.isFinite(progress.current) ? progress.current : "?";
    const total = Number.isFinite(progress.total) ? progress.total : "?";
    if (Number.isFinite(progress.submitted) && progress.submitted > progress.current) {
      const submittedPercent = Number.isFinite(progress.submittedPercent) ? `${progress.submittedPercent.toFixed(1)}% submitted` : "? submitted";
      const submitFps = Number.isFinite(progress.submitFps) ? `${progress.submitFps.toFixed(1)} submit fps` : "? submit fps";
      return `${label}: ${current}/${total} complete | ${progress.submitted}/${total} GPU submitted | ${submittedPercent} | ${submitFps}`;
    }
    const percent = Number.isFinite(progress.percent) ? `${progress.percent.toFixed(1)}% done` : "? done";
    const fps = Number.isFinite(progress.fps) ? `${progress.fps.toFixed(1)} fps` : "?";
    return `${label}: ${current}/${total} frames | ${percent} | ${fps}`;
  }
  if (progress.kind === "chunks") {
    const label = progress.label || "analysis";
    const current = Number.isFinite(progress.current) ? progress.current : "?";
    const total = Number.isFinite(progress.total) ? progress.total : "?";
    return `${label}: chunk ${current}/${total} complete`;
  }
  return progress.message || "";
}

function withProgress(job, message) {
  const progress = formatProgress(job && job.progress);
  if (progress && message) return `${progress}\n${message}`;
  return progress || message || "";
}

function jobStatusText(job) {
  const stage = job.stage || job.status || "";
  const message = /^progress\s+/.test(job.message || "") ? "" : (job.message || "");
  const status = message ? `${stage}: ${message}` : stage;
  const schemaVersion = (job && job.cacheSchemaVersion) || (state.config && state.config.cacheSchemaVersion);
  const statusText = withProgress(job, status);
  if (!schemaVersion) return statusText;
  return `Writer schema: ${schemaVersion}\n${statusText}`;
}

function renderBatchSummary(result) {
  const summary = result && result.summary;
  el.batchSummary.textContent = "";
  if (!summary) {
    el.batchSummary.classList.add("hidden");
    return;
  }
  el.batchSummary.classList.remove("hidden");
  const header = document.createElement("div");
  header.className = summary.fcpImportReady ? "status-ready" : "status-error";
  const sourceCounts = Number.isFinite(summary.sourceSuccessCount) && Number.isFinite(summary.sourceFailureCount)
    ? ` | Sources ${summary.sourceSuccessCount} ok / ${summary.sourceFailureCount} failed`
    : "";
  header.textContent = `${summary.fcpImportReady ? "FCP import ready" : "FCP import blocked"}${sourceCounts}`;
  el.batchSummary.appendChild(header);

  const counts = document.createElement("div");
  counts.className = "summary-grid";
  const countItems = [
    ["Analyzed", `${summary.analyzedSuccessCount || 0} ok / ${summary.analyzedFailureCount || 0} failed`],
    ["Packages", `${summary.packageCreatedCount || 0}`],
    ["Validation", `${summary.validationPassCount || 0} pass / ${summary.validationFailCount || 0} fail`],
    ["Event Cache", `${summary.eventCacheInstallPassCount || 0} installed / ${summary.eventCacheInstallFailCount || 0} fail`],
  ];
  for (const [label, value] of countItems) {
    const item = document.createElement("div");
    item.innerHTML = "<strong></strong><span></span>";
    item.querySelector("strong").textContent = label;
    item.querySelector("span").textContent = value;
    counts.appendChild(item);
  }
  el.batchSummary.appendChild(counts);

  const packages = Array.isArray(summary.packages) ? summary.packages : [];
  if (packages.length) {
    const list = document.createElement("div");
    list.className = "package-list";
    for (const pkg of packages) {
      const row = document.createElement("div");
      row.className = "package-item";
      const sample = pkg.sampleScalePercent ? `${pkg.sampleScalePercent}%` : "?";
      const pixels = pkg.sampleWidth && pkg.sampleHeight ? `${pkg.sampleWidth}x${pkg.sampleHeight}` : "?";
      const cacheInstall = pkg.eventCacheInstalled ? "event cache installed" : "event cache pending";
      const effectStack = pkg.sourceEffectStack || {};
      const inheritedEffects = Number(effectStack.inheritedFilterCount || 0);
      const effectStatus = inheritedEffects > 0
        ? `${inheritedEffects} inherited effect${inheritedEffects === 1 ? "" : "s"}`
        : (effectStack.unavailableReason || "no inherited effects");
      row.innerHTML = "<strong></strong><span></span><code></code>";
      row.querySelector("strong").textContent = `${pkg.importReady ? "Ready" : "Blocked"} | ${pkg.sourceName || "Source"}`;
      row.querySelector("span").textContent = `sample ${sample} (${pixels}) | schema ${pkg.cacheSchemaVersion || "?"} | ${pkg.cacheIdentityShort || "no identity"} | ${cacheInstall} | ${effectStatus}`;
      row.querySelector("code").textContent = pkg.fcpxmldPath || pkg.packagePath || "";
      list.appendChild(row);
    }
    el.batchSummary.appendChild(list);
  }

  const failed = Array.isArray(summary.failedClips) ? summary.failedClips : [];
  if (failed.length) {
    const failures = document.createElement("div");
    failures.className = "failure-list";
    failures.textContent = failed.map((item) => {
      const prefix = item.sourceName ? `${item.sourceName}: ` : "";
      return `${prefix}${item.reason || item.packagePath || "failed"}`;
    }).join("\n");
    el.batchSummary.appendChild(failures);
  }
}

function renderRestoreSummary(item) {
  el.restoreSummary.textContent = "";
  if (!item) {
    el.restoreSummary.classList.add("hidden");
    return;
  }
  el.restoreSummary.classList.remove("hidden");
  const rows = [
    ["Clip", item.footageFileName || item.footageName || "-"],
    ["Event", item.eventName || "-"],
    ["Schema", item.cacheSchemaVersion ? `schema ${item.cacheSchemaVersion}` : "-"],
    ["Sample", item.sampleWidth && item.sampleHeight ? `${item.sampleScalePercent || "?"}% | ${item.sampleWidth}x${item.sampleHeight}` : "-"],
    ["Frames", item.frameCount ? `${item.frameCount}` : "-"],
    ["Identity", item.cacheIdentityShort || "no short identity"],
    ["Package", item.name || "-"],
    ["Target Event", item.eventRoot || "-"],
  ];
  for (const [label, value] of rows) {
    const row = document.createElement("div");
    row.className = "restore-item";
    row.innerHTML = "<strong></strong><span></span>";
    row.querySelector("strong").textContent = label;
    row.querySelector("span").textContent = value;
    el.restoreSummary.appendChild(row);
  }
  if (Array.isArray(item.warnings) && item.warnings.length) {
    const warning = document.createElement("div");
    warning.className = "failure-list";
    warning.textContent = item.warnings.join("\n");
    el.restoreSummary.appendChild(warning);
  }
}

function updateRestoreState() {
  const item = state.restorePackage;
  const installation = state.restoreInstallation;
  if (item) el.restorePackagePathInput.value = item.packagePath;
  el.installRestorePackageButton.disabled = !item;
  el.revealRestorePackageButton.disabled = !item;
  el.openRestoreImportButton.disabled = !item || !item.fcpxmldPath;
  el.revealInstalledCacheButton.disabled = !installation || !installation.cacheRoot;
  renderRestoreSummary(item);
}

function attachRunningJob(job) {
  if (!job || (job.status !== "running" && job.status !== "cancelling")) {
    return false;
  }
  state.currentJobId = job.id;
  el.runButton.disabled = true;
  el.cancelButton.disabled = job.status === "cancelling";
  el.cancelButton.classList.remove("hidden");
  setStatus(jobStatusText(job));
  pollJob();
  return true;
}

function readStoredPreset(key) {
  try {
    const text = window.localStorage.getItem(key);
    return text ? JSON.parse(text) : null;
  } catch {
    return null;
  }
}

function normalizePreset(preset) {
  if (!preset) return null;
  if (preset.version === 2 && Array.isArray(preset.sourceJobs)) {
    const sourceJobs = preset.sourceJobs
      .map((job) => ({
        sourcePath: job.sourcePath || "",
        sourceItem: job.sourceItem || currentExportItem(job.sourcePath || ""),
        assetIds: Array.isArray(job.assetIds) ? job.assetIds.filter(Boolean) : [],
        importsDir: job.importsDir || job.cacheRoot || "",
        cacheRoot: job.cacheRoot || job.importsDir || "",
      }))
      .filter((job) => job.sourcePath && job.assetIds.length);
    if (!sourceJobs.length) return null;
    return {
      version: 2,
      sourceJobs,
      sampleScalePercent: preset.sampleScalePercent,
      savedAt: preset.savedAt,
    };
  }
  if (preset.version === 1 && preset.sourcePath) {
    const assetIds = Array.isArray(preset.assetIds) ? preset.assetIds.filter(Boolean) : [];
    if (!assetIds.length) return null;
    return {
      version: 2,
      sourceJobs: [{
        sourcePath: preset.sourcePath,
        sourceItem: preset.sourceItem || currentExportItem(preset.sourcePath),
        assetIds,
        importsDir: preset.importsDir || preset.cacheRoot || "",
        cacheRoot: preset.cacheRoot || preset.importsDir || "",
      }],
      sampleScalePercent: preset.sampleScalePercent,
      savedAt: preset.savedAt,
    };
  }
  return null;
}

function readLastAnalysisSettings() {
  return normalizePreset(readStoredPreset(LAST_ANALYSIS_STORAGE_KEY))
    || normalizePreset(readStoredPreset(LEGACY_LAST_ANALYSIS_STORAGE_KEY));
}

function updateLastAnalysisState() {
  const preset = readLastAnalysisSettings();
  el.lastAnalysisButton.disabled = !preset;
  if (!preset) {
    el.lastAnalysisButton.title = "Run analysis once to create a Last Analysis setting";
    return;
  }
  const firstSource = preset.sourceJobs[0] && preset.sourceJobs[0].sourcePath;
  const suffix = preset.sourceJobs.length > 1 ? ` + ${preset.sourceJobs.length - 1} more` : "";
  el.lastAnalysisButton.title = `Load ${firstSource || "last analysis"}${suffix}`;
}

function lowerPath(sourcePath) {
  return String(sourcePath || "").toLowerCase();
}

function isFcpbundlePath(sourcePath) {
  return lowerPath(sourcePath).endsWith(".fcpbundle");
}

function exportKindForPath(sourcePath) {
  const lowered = lowerPath(sourcePath);
  if (lowered.endsWith(".fcpbundle")) return "fcpbundle";
  if (lowered.endsWith(".fcpxmld")) return "fcpxmld";
  return "fcpxml";
}

function exportNameForPath(sourcePath) {
  const parts = String(sourcePath || "").split("/");
  return parts[parts.length - 1] || sourcePath;
}

function dirname(sourcePath) {
  const parts = String(sourcePath || "").split("/");
  parts.pop();
  return parts.join("/") || "/";
}

function joinPath(parent, child) {
  if (!parent || parent === "/") return `/${child}`;
  return `${parent.replace(/\/+$/, "")}/${child}`;
}

function defaultImportsDirForSource(sourcePath) {
  if (!sourcePath) return "";
  const name = exportNameForPath(sourcePath);
  const parent = dirname(sourcePath);
  if (isFcpbundlePath(sourcePath)) {
    return joinPath(joinPath(parent, DEFAULT_ANALYSIS_DIR_NAME), retainedAnalysisBundleDirName(name));
  }
  if (name === "Info.fcpxml" && exportNameForPath(parent).endsWith(".fcpxmld")) {
    return joinPath(dirname(parent), DEFAULT_ANALYSIS_DIR_NAME);
  }
  return joinPath(parent, DEFAULT_ANALYSIS_DIR_NAME);
}

function retainedAnalysisBundleDirName(name) {
  return String(name || "").replace(/\.fcpbundle$/i, "_fcpbundle");
}

function currentExportItem(sourcePath) {
  return state.sources.find((item) => item.path === sourcePath) || {
    name: exportNameForPath(sourcePath),
    path: sourcePath,
    importsDir: defaultImportsDirForSource(sourcePath),
    kind: exportKindForPath(sourcePath),
    mtimeMs: Date.now(),
  };
}

function activeSources() {
  if (state.sources.length) return state.sources;
  const typedPath = el.sourcePathInput.value.trim();
  return typedPath ? [currentExportItem(typedPath)] : [];
}

function clipKey(sourcePath, assetId) {
  return JSON.stringify([sourcePath, assetId]);
}

function shouldListAsset(asset) {
  return !String((asset && asset.name) || "").toLowerCase().includes(HIDDEN_CLIP_NAME_TOKEN);
}

function selectedClipCountForSource(sourcePath) {
  return state.assets.filter((asset) => asset.sourcePath === sourcePath && state.selectedClipKeys.has(clipKey(asset.sourcePath, asset.assetId))).length;
}

function sourceAssetCount(sourcePath) {
  return state.assets.filter((asset) => asset.sourcePath === sourcePath).length;
}

function importsDirForSource(sourceItem) {
  if (state.importsOverride) return state.importsOverride;
  return sourceItem.importsDir || defaultImportsDirForSource(sourceItem.path);
}

function updateImportsInput() {
  if (state.importsOverride) {
    el.cacheRootInput.value = state.importsOverride;
    return;
  }
  const sources = activeSources();
  if (sources.length === 1) {
    el.cacheRootInput.value = importsDirForSource(sources[0]);
  } else if (sources.length > 1) {
    el.cacheRootInput.value = `${sources.length} source-specific ${DEFAULT_ANALYSIS_DIR_NAME} folders`;
  } else {
    el.cacheRootInput.value = state.config ? (state.config.cacheRoot || "") : "";
  }
}

function saveLastAnalysisSettings(settings = null) {
  const sourceJobs = settings && Array.isArray(settings.sourceJobs)
    ? settings.sourceJobs
    : runBody().sourceJobs;
  const selectedJobs = sourceJobs
    .map((job) => ({
      sourcePath: job.sourcePath,
      sourceItem: job.sourceItem || currentExportItem(job.sourcePath),
      assetIds: Array.isArray(job.assetIds) ? job.assetIds.filter(Boolean) : [],
      importsDir: job.importsDir || job.cacheRoot || "",
      cacheRoot: job.cacheRoot || job.importsDir || "",
    }))
    .filter((job) => job.sourcePath && job.assetIds.length);
  if (!selectedJobs.length) return;
  const preset = {
    version: 2,
    sourceJobs: selectedJobs,
    sampleScalePercent: settings ? settings.sampleScalePercent : Number(el.sampleScaleInput.value),
    savedAt: Date.now(),
  };
  try {
    window.localStorage.setItem(LAST_ANALYSIS_STORAGE_KEY, JSON.stringify(preset));
    updateLastAnalysisState();
  } catch {
    setStatus("Last analysis could not be saved in this browser.", "error");
  }
}

function formatMtime(ms) {
  return new Date(ms).toLocaleString();
}

function formatDuration(asset) {
  if (asset.durationTimecode) return `${asset.durationTimecode} (${asset.durationSeconds}s)`;
  if (asset.durationSeconds) return `${asset.durationSeconds}s`;
  return "-";
}

function formatAssetStatus(asset) {
  if (asset.supported) return "Original ready";
  if ((asset.unsupported || "").startsWith("Broken original link")) return "Broken original link";
  return asset.unsupported || "Unsupported";
}

function renderExports(items = state.sources) {
  state.sources = items;
  el.exportsList.textContent = "";
  updateImportsInput();
  if (!items.length) {
    const empty = document.createElement("div");
    empty.className = "export-item";
    empty.innerHTML = "<strong>No source selected</strong><span></span>";
    el.exportsList.appendChild(empty);
    return;
  }
  for (const item of items) {
    const row = document.createElement("button");
    row.type = "button";
    row.className = `export-item${item.path === state.activeSourcePath ? " selected" : ""}`;
    row.innerHTML = "<strong></strong><span></span><span></span><span></span>";
    row.querySelector("strong").textContent = item.name;
    const spans = row.querySelectorAll("span");
    const selectedCount = selectedClipCountForSource(item.path);
    const loadedCount = sourceAssetCount(item.path);
    spans[0].textContent = `${item.kind} | ${formatMtime(item.mtimeMs)}`;
    spans[1].textContent = loadedCount ? `${selectedCount}/${loadedCount} clip(s) selected` : "Not loaded";
    spans[2].textContent = item.path;
    row.addEventListener("click", () => {
      state.activeSourcePath = item.path;
      el.sourcePathInput.value = item.path;
      updateImportsInput();
      renderExports();
    });
    el.exportsList.appendChild(row);
  }
}

function renderAssets() {
  el.assetsBody.textContent = "";
  for (const asset of state.assets) {
    const key = clipKey(asset.sourcePath, asset.assetId);
    const selected = state.selectedClipKeys.has(key);
    const row = document.createElement("tr");
    if (selected) row.className = "selected";
    row.innerHTML = `
      <td class="radio-cell"><input type="checkbox"></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
    `;
    const checkbox = row.querySelector("input");
    checkbox.checked = selected;
    checkbox.disabled = !asset.supported;
    const cells = row.querySelectorAll("td");
    cells[1].textContent = asset.sourceName || exportNameForPath(asset.sourcePath);
    cells[1].title = asset.sourcePath;
    cells[2].textContent = asset.name || asset.assetId;
    cells[3].textContent = asset.eventName || "-";
    cells[4].textContent = formatDuration(asset);
    cells[5].textContent = `${asset.width || "?"}x${asset.height || "?"} | ${asset.frameDuration || "fps ?"}`;
    const mediaKind = asset.mediaKind === "original-media" || asset.mediaKind === "asset-src"
      ? "Original"
      : asset.mediaKind || "Unknown";
    cells[6].textContent = asset.mediaPath ? `${mediaKind}: ${asset.mediaPath}` : "";
    cells[7].textContent = formatAssetStatus(asset);
    cells[7].title = asset.unsupported || "";
    cells[7].className = asset.supported ? "status-ready" : "status-error";
    checkbox.addEventListener("change", () => {
      if (checkbox.checked) {
        state.selectedClipKeys.add(key);
      } else {
        state.selectedClipKeys.delete(key);
      }
      renderAssets();
    });
    row.addEventListener("click", (event) => {
      if (event.target !== checkbox && asset.supported) {
        if (state.selectedClipKeys.has(key)) {
          state.selectedClipKeys.delete(key);
        } else {
          state.selectedClipKeys.add(key);
        }
        renderAssets();
      }
    });
    el.assetsBody.appendChild(row);
  }
  renderExports();
  updateRunState();
}

function updateRunState() {
  const count = state.selectedClipKeys.size;
  const sourceCount = new Set(state.assets.filter((asset) => state.selectedClipKeys.has(clipKey(asset.sourcePath, asset.assetId))).map((asset) => asset.sourcePath)).size;
  el.selectedText.textContent = count ? `${count} media selected from ${sourceCount} source(s)` : "No media selected";
  el.runButton.disabled = Boolean(state.currentJobId) || count === 0 || sourceCount === 0;
}

async function loadConfig() {
  state.config = await api("/api/config");
  renderAppVersion(state.config.appVersion || window.STABILIZER_EVENT_ANALYZER_VERSION, state.config);
  el.sampleScaleInput.value = String(state.config.defaultSampleScalePercent || 100);
  const schemaText = state.config.cacheSchemaVersion ? ` | Writer schema: ${state.config.cacheSchemaVersion}` : "";
  const analysisDirName = state.config.defaultAnalysisDirName || DEFAULT_ANALYSIS_DIR_NAME;
  el.configText.textContent = `Imports: ${analysisDirName} next to selected export${schemaText} | ${state.config.repoRoot || ""}`;
  renderExports([]);
  updateLastAnalysisState();
  updateRunState();
  updateRestoreState();
  setRestoreStatus("Select a saved per-clip package folder to restore its analysis cache.");
  await resumeLatestJob();
}

async function resumeLatestJob() {
  if (state.currentJobId) return;
  const payload = await api("/api/latest-job");
  attachRunningJob(payload.job);
}

async function selectExportFiles() {
  setStatus("Selecting source files...");
  const payload = await api("/api/select-exports", {
    method: "POST",
  });
  const items = payload.items || [];
  state.sources = items;
  state.activeSourcePath = items[0] ? items[0].path : "";
  el.sourcePathInput.value = state.activeSourcePath;
  state.importsOverride = "";
  state.assets = [];
  state.selectedClipKeys.clear();
  renderExports(items);
  renderAssets();
  const rejected = payload.rejected || [];
  const rejectionText = rejected.length ? ` (${rejected.length} rejected)` : "";
  if (!items.length) {
    setStatus(rejected.length ? rejected.map((item) => item.reason).join("\n") : "No source selected.", rejected.length ? "error" : "");
    return;
  }
  setStatus(`Selected ${items.length} source(s)${rejectionText}. Loading Event Media...`, rejected.length ? "error" : "ok");
  await loadAssets();
}

async function loadAssets() {
  let sources = activeSources();
  if (!sources.length) {
    setStatus("Set an FCP library, FCPXMLD, or Info.fcpxml path.", "error");
    return;
  }
  if (!state.sources.length) {
    state.sources = sources;
    state.activeSourcePath = sources[0].path;
    renderExports();
  }
  sources = activeSources();
  state.assets = [];
  state.selectedClipKeys.clear();
  state.lastResult = null;
  el.resultActions.classList.add("hidden");
  renderBatchSummary(null);
  renderAssets();
  setStatus(`Loading Event media from ${sources.length} source(s)...`);
  let loadedSourceCount = 0;
  let failedSourceCount = 0;
  const errors = [];
  try {
    for (const [index, source] of sources.entries()) {
      setStatus(`Loading Event media ${index + 1}/${sources.length}: ${source.name || source.path}`);
      try {
        const payload = await api("/api/assets", {
          method: "POST",
          body: { sourcePath: source.path },
        });
        const sourceAssets = (payload.assets || [])
          .filter(shouldListAsset)
          .map((asset) => ({
            ...asset,
            sourcePath: source.path,
            sourceName: source.name || exportNameForPath(source.path),
            sourceKind: source.kind || exportKindForPath(source.path),
            sourceInfoPath: payload.infoPath,
            sourcePackagePath: payload.packagePath,
            sourceEventNames: payload.eventNames || [],
          }));
        state.assets.push(...sourceAssets);
        loadedSourceCount += 1;
        if (state.pendingPresetClipKeys) {
          for (const asset of sourceAssets) {
            const key = clipKey(asset.sourcePath, asset.assetId);
            if (asset.supported && state.pendingPresetClipKeys.has(key)) {
              state.selectedClipKeys.add(key);
            }
          }
        } else if (!isFcpbundlePath(source.path)) {
          for (const asset of sourceAssets) {
            if (asset.supported) state.selectedClipKeys.add(clipKey(asset.sourcePath, asset.assetId));
          }
        }
      } catch (error) {
        failedSourceCount += 1;
        errors.push(`${source.name || source.path}: ${error.message}`);
      }
    }
    state.pendingPresetClipKeys = null;
    renderAssets();
    const supportedCount = state.assets.filter((asset) => asset.supported).length;
    const fcpbundleCount = sources.filter((source) => isFcpbundlePath(source.path)).length;
    const selectHint = fcpbundleCount ? " FCP library clips remain unselected until you choose them." : "";
    el.sourceText.textContent = `${loadedSourceCount}/${sources.length} source(s) loaded | ${supportedCount}/${state.assets.length} supported clip(s)`;
    const statusKind = failedSourceCount ? "error" : "ok";
    const errorText = errors.length ? `\n${errors.join("\n")}` : "";
    setStatus(`Loaded ${loadedSourceCount}/${sources.length} source(s), ${supportedCount}/${state.assets.length} supported Event media asset(s).${selectHint}${errorText}`, statusKind);
  } catch (error) {
    renderAssets();
    setStatus(error.message, "error");
  }
}

async function applyLastAnalysis() {
  const preset = readLastAnalysisSettings();
  if (!preset) {
    setStatus("No last analysis saved yet.", "error");
    updateLastAnalysisState();
    return;
  }
  const sourceJobs = preset.sourceJobs || [];
  const sourceItems = sourceJobs.map((job) => ({
    ...currentExportItem(job.sourcePath),
    ...(job.sourceItem || {}),
    path: job.sourcePath,
    importsDir: job.importsDir || job.cacheRoot || (job.sourceItem && job.sourceItem.importsDir) || defaultImportsDirForSource(job.sourcePath),
  }));
  state.sources = sourceItems;
  state.activeSourcePath = sourceItems[0] ? sourceItems[0].path : "";
  el.sourcePathInput.value = state.activeSourcePath;
  state.importsOverride = "";
  state.pendingPresetClipKeys = new Set();
  for (const job of sourceJobs) {
    for (const assetId of job.assetIds || []) {
      state.pendingPresetClipKeys.add(clipKey(job.sourcePath, assetId));
    }
  }
  if (preset.sampleScalePercent) el.sampleScaleInput.value = String(preset.sampleScalePercent);
  renderExports(sourceItems);
  setStatus("Loading last analysis...");
  await loadAssets();
  const selectedCount = state.selectedClipKeys.size;
  if (selectedCount === 0) {
    setStatus("Last analysis loaded, but none of the saved clips matched the selected source(s).", "error");
    return;
  }
  setStatus(`Last analysis loaded: ${selectedCount} clip(s) selected from ${sourceItems.length} source(s).`, "ok");
}

async function selectCacheRoot() {
  setStatus("Selecting Imports folder...");
  const payload = await api("/api/select-cache-root", {
    method: "POST",
  });
  if (!payload.item) {
    setStatus("No Imports folder selected.");
    return;
  }
  state.importsOverride = payload.item.path;
  updateImportsInput();
  updateRunState();
  setStatus(`Selected Imports: ${payload.item.path}`, "ok");
}

async function selectRestorePackage() {
  setRestoreStatus("Selecting package folder...");
  const payload = await api("/api/select-restore-package", { method: "POST" });
  if (!payload.item) {
    setRestoreStatus("No package folder selected.");
    return;
  }
  state.restorePackage = payload.item;
  state.restoreInstallation = null;
  updateRestoreState();
  const warningText = payload.item.warnings && payload.item.warnings.length ? `\n${payload.item.warnings.join("\n")}` : "";
  setRestoreStatus(`Package ready: ${payload.item.footageFileName || payload.item.footageName || payload.item.name}${warningText}`, warningText ? "error" : "ok");
}

async function loadRestorePackagePath() {
  const packagePath = el.restorePackagePathInput.value.trim();
  if (!packagePath) {
    setRestoreStatus("Enter or select a package folder path.", "error");
    return;
  }
  setRestoreStatus("Reading package folder...");
  const payload = await api("/api/restore-package-info", {
    method: "POST",
    body: { packagePath },
  });
  state.restorePackage = payload.item;
  state.restoreInstallation = null;
  updateRestoreState();
  const warningText = payload.item.warnings && payload.item.warnings.length ? `\n${payload.item.warnings.join("\n")}` : "";
  setRestoreStatus(`Package ready: ${payload.item.footageFileName || payload.item.footageName || payload.item.name}${warningText}`, warningText ? "error" : "ok");
}

async function installRestorePackage() {
  if (!state.restorePackage) {
    setRestoreStatus("Select a package folder first.", "error");
    return;
  }
  el.installRestorePackageButton.disabled = true;
  setRestoreStatus("Installing cache into the package's Event Analysis Files...");
  try {
    const payload = await api("/api/install-restore-package", {
      method: "POST",
      body: { packagePath: state.restorePackage.packagePath },
    });
    state.restorePackage = payload.item;
    state.restoreInstallation = payload.installation;
    updateRestoreState();
    setRestoreStatus(`Installed cache: ${payload.installation.cacheRoot}`, "ok");
  } catch (error) {
    updateRestoreState();
    setRestoreStatus(error.message, "error");
  }
}

function runBody() {
  const sources = activeSources();
  const sourceJobs = [];
  for (const source of sources) {
    const assetIds = state.assets
      .filter((asset) => asset.sourcePath === source.path && state.selectedClipKeys.has(clipKey(asset.sourcePath, asset.assetId)))
      .map((asset) => asset.assetId);
    if (!assetIds.length) continue;
    const importsDir = importsDirForSource(source);
    sourceJobs.push({
      sourcePath: source.path,
      sourceItem: source,
      cacheRoot: importsDir,
      importsDir,
      outputDir: importsDir,
      assetIds,
    });
  }
  return {
    sourceJobs,
    sampleScalePercent: Number(el.sampleScaleInput.value),
  };
}

async function runAnalysis() {
  const body = runBody();
  if (!body.sourceJobs.length) {
    setStatus("Select at least one supported clip.", "error");
    return;
  }
  setStatus(`Queueing serial analysis for ${body.sourceJobs.length} source(s)...`);
  el.resultActions.classList.add("hidden");
  renderBatchSummary(null);
  const payload = await api("/api/run", { method: "POST", body });
  saveLastAnalysisSettings(body);
  state.currentJobId = payload.job.id;
  el.runButton.disabled = true;
  el.cancelButton.disabled = false;
  el.cancelButton.classList.remove("hidden");
  pollJob();
}

async function pollJob() {
  if (!state.currentJobId) return;
  try {
    const payload = await api(`/api/job?id=${encodeURIComponent(state.currentJobId)}`);
    const job = payload.job;
    setStatus(jobStatusText(job));
    if (job.status === "done") {
      state.lastResult = job.result;
      renderBatchSummary(job.result);
      const summary = job.result.summary || {};
      const sourceFailures = summary.sourceFailureCount || 0;
      const message = `Done: ${summary.packageCreatedCount || job.result.resultCount || 0} package(s), ${summary.validationPassCount || 0} validation pass, ${sourceFailures} source failure(s).`;
      setStatus(withProgress(job, message), summary.fcpImportReady ? "ok" : "error");
      state.currentJobId = "";
      el.cancelButton.classList.add("hidden");
      el.cancelButton.disabled = false;
      el.resultActions.classList.remove("hidden");
      updateRunState();
      return;
    }
    if (job.status === "error" || job.status === "cancelled") {
      if (job.result) renderBatchSummary(job.result);
      setStatus(withProgress(job, job.error || job.message || job.status), "error");
      state.currentJobId = "";
      el.cancelButton.classList.add("hidden");
      el.cancelButton.disabled = false;
      updateRunState();
      return;
    }
    setTimeout(pollJob, 1200);
  } catch (error) {
    setStatus(error.message, "error");
    state.currentJobId = "";
    el.cancelButton.classList.add("hidden");
    el.cancelButton.disabled = false;
    updateRunState();
  }
}

async function cancelJob() {
  if (!state.currentJobId) return;
  el.cancelButton.disabled = true;
  await api("/api/cancel", { method: "POST", body: { id: state.currentJobId } });
  setStatus("Cancelling...");
}

async function reveal(pathValue) {
  if (!pathValue) return;
  await api("/api/reveal", { method: "POST", body: { path: pathValue } });
}

async function openPath(pathValue) {
  if (!pathValue) return;
  await api("/api/open", { method: "POST", body: { path: pathValue } });
}

function restoreInstalledCachePath() {
  return state.restoreInstallation && state.restoreInstallation.cacheRoot ? state.restoreInstallation.cacheRoot : "";
}

function firstImportPath(result) {
  if (!result) return "";
  if (result.outputPackage) return result.outputPackage;
  if (Array.isArray(result.outputPackages) && result.outputPackages[0]) return result.outputPackages[0];
  const packages = result.summary && Array.isArray(result.summary.packages) ? result.summary.packages : [];
  return (packages[0] && (packages[0].fcpxmldPath || packages[0].packagePath)) || "";
}

function firstCachePath(result) {
  if (!result) return "";
  if (result.cacheRoot) return result.cacheRoot;
  const sourceResults = Array.isArray(result.sourceResults) ? result.sourceResults : [];
  const readySource = sourceResults.find((item) => item && item.cacheRoot);
  if (readySource) return readySource.cacheRoot;
  const packages = result.summary && Array.isArray(result.summary.packages) ? result.summary.packages : [];
  const readyPackage = packages.find((item) => item && item.eventCacheRoot);
  return (readyPackage && readyPackage.eventCacheRoot) || "";
}

el.selectExportFilesButton.addEventListener("click", () => selectExportFiles().catch((error) => setStatus(error.message, "error")));
el.lastAnalysisButton.addEventListener("click", () => applyLastAnalysis().catch((error) => setStatus(error.message, "error")));
el.selectCacheRootButton.addEventListener("click", () => selectCacheRoot().catch((error) => setStatus(error.message, "error")));
el.selectRestorePackageButton.addEventListener("click", () => selectRestorePackage().catch((error) => setRestoreStatus(error.message, "error")));
el.loadRestorePackageButton.addEventListener("click", () => loadRestorePackagePath().catch((error) => setRestoreStatus(error.message, "error")));
el.installRestorePackageButton.addEventListener("click", () => installRestorePackage());
el.loadAssetsButton.addEventListener("click", () => loadAssets().catch((error) => setStatus(error.message, "error")));
el.sourcePathInput.addEventListener("input", () => {
  if (!state.sources.length) updateImportsInput();
});
el.selectAllButton.addEventListener("click", () => {
  for (const asset of state.assets) {
    if (asset.supported) state.selectedClipKeys.add(clipKey(asset.sourcePath, asset.assetId));
  }
  renderAssets();
});
el.clearSelectionButton.addEventListener("click", () => {
  state.selectedClipKeys.clear();
  renderAssets();
});
el.cacheRootInput.addEventListener("input", updateRunState);
el.restorePackagePathInput.addEventListener("input", () => {
  if (state.restorePackage && el.restorePackagePathInput.value.trim() !== state.restorePackage.packagePath) {
    state.restorePackage = null;
    state.restoreInstallation = null;
    updateRestoreState();
    setRestoreStatus("Load the package path before installing cache.");
  }
});
el.runButton.addEventListener("click", () => runAnalysis().catch((error) => setStatus(error.message, "error")));
el.cancelButton.addEventListener("click", () => cancelJob().catch((error) => setStatus(error.message, "error")));
el.revealCacheButton.addEventListener("click", () => reveal(firstCachePath(state.lastResult)));
el.revealImportButton.addEventListener("click", () => reveal(firstImportPath(state.lastResult)));
el.openImportButton.addEventListener("click", () => openPath(firstImportPath(state.lastResult)));
el.revealRestorePackageButton.addEventListener("click", () => reveal(state.restorePackage && state.restorePackage.packagePath));
el.revealInstalledCacheButton.addEventListener("click", () => reveal(restoreInstalledCachePath()));
el.openRestoreImportButton.addEventListener("click", () => openPath(state.restorePackage && state.restorePackage.fcpxmldPath));

loadConfig()
  .catch((error) => setStatus(error.message, "error"));
