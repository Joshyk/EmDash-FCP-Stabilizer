"use strict";

const LAST_ANALYSIS_STORAGE_KEY = "tokyoWalkingStabilizer.eventAnalyzer.lastAnalysis.v1";

const state = {
  config: null,
  sourcePath: "",
  exportItems: [],
  assets: [],
  selectedAssetIds: new Set(),
  pendingPresetAssetIds: null,
  currentJobId: "",
  lastResult: null,
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
};

function renderAppVersion(version) {
  el.versionText.textContent = version ? `v${version}` : "";
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
  return withProgress(job, status);
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
  header.textContent = summary.fcpImportReady ? "FCP import ready" : "FCP import blocked";
  el.batchSummary.appendChild(header);

  const counts = document.createElement("div");
  counts.className = "summary-grid";
  const countItems = [
    ["Analyzed", `${summary.analyzedSuccessCount || 0} ok / ${summary.analyzedFailureCount || 0} failed`],
    ["Packages", `${summary.packageCreatedCount || 0}`],
    ["Validation", `${summary.validationPassCount || 0} pass / ${summary.validationFailCount || 0} fail`],
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
      row.innerHTML = "<strong></strong><span></span><code></code>";
      row.querySelector("strong").textContent = pkg.importReady ? "Ready" : "Blocked";
      row.querySelector("span").textContent = `sample ${sample} (${pixels}) | schema ${pkg.cacheSchemaVersion || "?"} | ${pkg.cacheIdentityShort || "no identity"}`;
      row.querySelector("code").textContent = pkg.packagePath || pkg.fcpxmldPath || "";
      list.appendChild(row);
    }
    el.batchSummary.appendChild(list);
  }

  const failed = Array.isArray(summary.failedClips) ? summary.failedClips : [];
  if (failed.length) {
    const failures = document.createElement("div");
    failures.className = "failure-list";
    failures.textContent = failed.map((item) => item.reason || item.packagePath || "failed").join("\n");
    el.batchSummary.appendChild(failures);
  }
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

function readLastAnalysisSettings() {
  try {
    const text = window.localStorage.getItem(LAST_ANALYSIS_STORAGE_KEY);
    if (!text) return null;
    const preset = JSON.parse(text);
    if (!preset || preset.version !== 1 || !preset.sourcePath) return null;
    return preset;
  } catch {
    return null;
  }
}

function updateLastAnalysisState() {
  const preset = readLastAnalysisSettings();
  el.lastAnalysisButton.disabled = !preset;
  el.lastAnalysisButton.title = preset
    ? `Load ${preset.sourcePath}`
    : "Run analysis once to create a Last Analysis setting";
}

function exportKindForPath(sourcePath) {
  return sourcePath.endsWith(".fcpxmld") ? "fcpxmld" : "fcpxml";
}

function exportNameForPath(sourcePath) {
  const parts = sourcePath.split("/");
  return parts[parts.length - 1] || sourcePath;
}

function dirname(sourcePath) {
  const parts = sourcePath.split("/");
  parts.pop();
  return parts.join("/") || "/";
}

function defaultImportsDirForSource(sourcePath) {
  if (!sourcePath) return "";
  const name = exportNameForPath(sourcePath);
  const parent = dirname(sourcePath);
  if (name === "Info.fcpxml" && exportNameForPath(parent).endsWith(".fcpxmld")) {
    return dirname(parent);
  }
  if (name.endsWith(".fcpxmld")) {
    return parent;
  }
  return parent;
}

function currentExportItem(sourcePath) {
  return state.exportItems.find((item) => item.path === sourcePath) || {
    name: exportNameForPath(sourcePath),
    path: sourcePath,
    importsDir: defaultImportsDirForSource(sourcePath),
    kind: exportKindForPath(sourcePath),
    mtimeMs: Date.now(),
  };
}

function setImportsDirForSource(sourcePath, sourceItem = null) {
  el.cacheRootInput.value = (sourceItem && sourceItem.importsDir) || defaultImportsDirForSource(sourcePath);
  updateRunState();
}

function saveLastAnalysisSettings(settings = null) {
  const sourcePath = (settings && settings.sourcePath) || state.sourcePath || el.sourcePathInput.value.trim();
  const assetIds = settings && Array.isArray(settings.assetIds)
    ? settings.assetIds
    : Array.from(state.selectedAssetIds);
  const importsDir = (settings && settings.importsDir) || el.cacheRootInput.value.trim();
  if (!sourcePath || !assetIds.length) return;
  const preset = {
    version: 1,
    sourcePath,
    sourceItem: currentExportItem(sourcePath),
    assetIds,
    importsDir,
    cacheRoot: importsDir,
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

function renderExports(items) {
  state.exportItems = items;
  el.exportsList.textContent = "";
  if (!items.length) {
    const empty = document.createElement("div");
    empty.className = "export-item";
    empty.innerHTML = "<strong>No export files selected</strong><span></span>";
    el.exportsList.appendChild(empty);
    return;
  }
  for (const item of items) {
    const row = document.createElement("button");
    row.type = "button";
    row.className = `export-item${item.path === state.sourcePath ? " selected" : ""}`;
    row.innerHTML = "<strong></strong><span></span><span></span>";
    row.querySelector("strong").textContent = item.name;
    const spans = row.querySelectorAll("span");
    spans[0].textContent = `${item.kind} | ${formatMtime(item.mtimeMs)}`;
    spans[1].textContent = item.path;
    row.addEventListener("click", () => {
      state.sourcePath = item.path;
      el.sourcePathInput.value = item.path;
      setImportsDirForSource(item.path, item);
      loadAssets();
    });
    el.exportsList.appendChild(row);
  }
}

function renderAssets() {
  el.assetsBody.textContent = "";
  for (const asset of state.assets) {
    const selected = state.selectedAssetIds.has(asset.assetId);
    const row = document.createElement("tr");
    if (selected) row.className = "selected";
    row.innerHTML = `
      <td class="radio-cell"><input type="checkbox"></td>
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
    cells[1].textContent = asset.name || asset.assetId;
    cells[2].textContent = formatDuration(asset);
    cells[3].textContent = `${asset.width || "?"}x${asset.height || "?"} | ${asset.frameDuration || "fps ?"}`;
    const mediaKind = asset.mediaKind === "original-media" || asset.mediaKind === "asset-src"
      ? "Original"
      : asset.mediaKind || "Unknown";
    cells[4].textContent = asset.mediaPath ? `${mediaKind}: ${asset.mediaPath}` : "";
    cells[5].textContent = asset.supported ? "Original ready" : asset.unsupported || "Unsupported";
    cells[5].className = asset.supported ? "status-ready" : "status-error";
    checkbox.addEventListener("change", () => {
      if (checkbox.checked) {
        state.selectedAssetIds.add(asset.assetId);
      } else {
        state.selectedAssetIds.delete(asset.assetId);
      }
      renderAssets();
    });
    row.addEventListener("click", (event) => {
      if (event.target !== checkbox && asset.supported) {
        if (state.selectedAssetIds.has(asset.assetId)) {
          state.selectedAssetIds.delete(asset.assetId);
        } else {
          state.selectedAssetIds.add(asset.assetId);
        }
        renderAssets();
      }
    });
    el.assetsBody.appendChild(row);
  }
  updateRunState();
}

function updateRunState() {
  const count = state.selectedAssetIds.size;
  el.selectedText.textContent = count ? `${count} media selected` : "No media selected";
  el.runButton.disabled = Boolean(state.currentJobId) || !state.sourcePath || count === 0 || !el.cacheRootInput.value.trim();
}

async function loadConfig() {
  state.config = await api("/api/config");
  renderAppVersion(state.config.appVersion || window.STABILIZER_EVENT_ANALYZER_VERSION);
  el.cacheRootInput.value = state.config.cacheRoot || "";
  el.sampleScaleInput.value = String(state.config.defaultSampleScalePercent || 100);
  el.configText.textContent = "Imports: same folder as selected export";
  renderExports([]);
  updateLastAnalysisState();
  updateRunState();
  await resumeLatestJob();
}

async function resumeLatestJob() {
  if (state.currentJobId) return;
  const payload = await api("/api/latest-job");
  attachRunningJob(payload.job);
}

async function selectExportFiles() {
  setStatus("Selecting export files...");
  const payload = await api("/api/select-exports", {
    method: "POST",
  });
  renderExports(payload.items || []);
  const rejected = payload.rejected || [];
  const rejectionText = rejected.length ? ` (${rejected.length} rejected)` : "";
  if (!(payload.items || []).length) {
    setStatus(rejected.length ? rejected.map((item) => item.reason).join("\n") : "No export files selected.", rejected.length ? "error" : "");
    return;
  }
  const currentStillSelected = (payload.items || []).some((item) => item.path === state.sourcePath);
  if (!currentStillSelected) {
    state.sourcePath = payload.items[0].path;
    el.sourcePathInput.value = state.sourcePath;
    setImportsDirForSource(state.sourcePath, payload.items[0]);
    await loadAssets();
  }
  setStatus(`Selected ${(payload.items || []).length} export file(s)${rejectionText}.`, rejected.length ? "error" : "ok");
}

async function loadAssets() {
  state.sourcePath = el.sourcePathInput.value.trim();
  if (!el.cacheRootInput.value.trim()) {
    setImportsDirForSource(state.sourcePath);
  }
  state.assets = [];
  state.selectedAssetIds.clear();
  state.lastResult = null;
  el.resultActions.classList.add("hidden");
  renderBatchSummary(null);
  renderAssets();
  if (!state.sourcePath) {
    setStatus("Set an FCPXMLD or Info.fcpxml path.", "error");
    return;
  }
  setStatus("Loading Event media...");
  try {
    const payload = await api("/api/assets", {
      method: "POST",
      body: { sourcePath: state.sourcePath },
    });
    state.assets = payload.assets || [];
    el.sourceText.textContent = payload.packagePath || payload.infoPath || state.sourcePath;
    if (state.pendingPresetAssetIds) {
      for (const asset of state.assets) {
        if (asset.supported && state.pendingPresetAssetIds.has(asset.assetId)) {
          state.selectedAssetIds.add(asset.assetId);
        }
      }
      state.pendingPresetAssetIds = null;
    } else {
      for (const asset of state.assets) {
        if (asset.supported) state.selectedAssetIds.add(asset.assetId);
      }
    }
    renderAssets();
    setStatus(`Loaded ${state.assets.length} Event media asset(s).`, "ok");
  } catch (error) {
    renderAssets();
    setStatus(error.message, "error");
  }
}

async function applyLastAnalysis() {
  const preset = readLastAnalysisSettings();
  if (!preset || !preset.sourcePath) {
    setStatus("No last analysis saved yet.", "error");
    updateLastAnalysisState();
    return;
  }
  const assetIds = Array.isArray(preset.assetIds) ? preset.assetIds.filter(Boolean) : [];
  if (!assetIds.length) {
    setStatus("Last analysis has no saved clip selection.", "error");
    return;
  }
  const savedItem = preset.sourceItem && preset.sourceItem.path === preset.sourcePath
    ? preset.sourceItem
    : currentExportItem(preset.sourcePath);
  state.sourcePath = preset.sourcePath;
  el.sourcePathInput.value = preset.sourcePath;
  const nextItems = [
    savedItem,
    ...state.exportItems.filter((item) => item.path !== preset.sourcePath),
  ];
  renderExports(nextItems);
  state.pendingPresetAssetIds = new Set(assetIds);
  el.cacheRootInput.value = preset.importsDir || preset.cacheRoot || defaultImportsDirForSource(preset.sourcePath);
  if (preset.sampleScalePercent) el.sampleScaleInput.value = String(preset.sampleScalePercent);
  setStatus("Loading last analysis...");
  await loadAssets();
  const selectedCount = state.selectedAssetIds.size;
  if (selectedCount === 0) {
    setStatus("Last analysis loaded, but none of the saved clips matched this export.", "error");
    return;
  }
  setStatus(`Last analysis loaded: ${selectedCount} clip(s) selected.`, "ok");
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
  el.cacheRootInput.value = payload.item.path;
  updateRunState();
  setStatus(`Selected Imports: ${payload.item.path}`, "ok");
}

function runBody() {
  const importsDir = el.cacheRootInput.value.trim();
  return {
    sourcePath: state.sourcePath,
    cacheRoot: importsDir,
    importsDir,
    outputDir: importsDir,
    assetIds: Array.from(state.selectedAssetIds),
    sampleScalePercent: Number(el.sampleScaleInput.value),
  };
}

async function runAnalysis() {
  const body = runBody();
  setStatus("Queueing serial analysis...");
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
      setStatus(withProgress(job, `Done: ${summary.packageCreatedCount || job.result.resultCount} package(s), ${summary.validationPassCount || 0} validation pass.`), "ok");
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

el.selectExportFilesButton.addEventListener("click", () => selectExportFiles().catch((error) => setStatus(error.message, "error")));
el.lastAnalysisButton.addEventListener("click", () => applyLastAnalysis().catch((error) => setStatus(error.message, "error")));
el.selectCacheRootButton.addEventListener("click", () => selectCacheRoot().catch((error) => setStatus(error.message, "error")));
el.loadAssetsButton.addEventListener("click", loadAssets);
el.selectAllButton.addEventListener("click", () => {
  for (const asset of state.assets) {
    if (asset.supported) state.selectedAssetIds.add(asset.assetId);
  }
  renderAssets();
});
el.clearSelectionButton.addEventListener("click", () => {
  state.selectedAssetIds.clear();
  renderAssets();
});
el.cacheRootInput.addEventListener("input", updateRunState);
el.runButton.addEventListener("click", () => runAnalysis().catch((error) => setStatus(error.message, "error")));
el.cancelButton.addEventListener("click", () => cancelJob().catch((error) => setStatus(error.message, "error")));
el.revealCacheButton.addEventListener("click", () => reveal(state.lastResult && state.lastResult.cacheRoot));
el.revealImportButton.addEventListener("click", () => reveal(state.lastResult && state.lastResult.outputPackage));
el.openImportButton.addEventListener("click", () => openPath(state.lastResult && state.lastResult.outputPackage));

loadConfig()
  .catch((error) => setStatus(error.message, "error"));
