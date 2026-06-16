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
  maxFramesInput: document.getElementById("maxFramesInput"),
  runButton: document.getElementById("runButton"),
  cancelButton: document.getElementById("cancelButton"),
  statusBox: document.getElementById("statusBox"),
  progressText: document.getElementById("progressText"),
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

function clearProgress() {
  el.progressText.textContent = "";
  el.progressText.classList.add("hidden");
}

function formatProgress(progress) {
  if (!progress) return "";
  if (progress.kind === "frames") {
    const label = progress.label || "analysis";
    const current = Number.isFinite(progress.current) ? progress.current : "?";
    const total = Number.isFinite(progress.total) ? progress.total : "?";
    const percent = Number.isFinite(progress.percent) ? `${progress.percent.toFixed(1)}%` : "?";
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

function renderProgress(progress) {
  const text = formatProgress(progress);
  if (!text) {
    clearProgress();
    return;
  }
  el.progressText.textContent = text;
  el.progressText.classList.remove("hidden");
}

function jobStatusText(job) {
  const stage = job.stage || job.status || "";
  const message = /^progress\s+/.test(job.message || "") ? "" : (job.message || "");
  return message ? `${stage}: ${message}` : stage;
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
    maxFrames: settings ? settings.maxFrames : (el.maxFramesInput.value ? Number(el.maxFramesInput.value) : null),
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
  el.maxFramesInput.value = preset.maxFrames ? String(preset.maxFrames) : "";
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
    maxFrames: el.maxFramesInput.value ? Number(el.maxFramesInput.value) : null,
  };
}

async function runAnalysis() {
  const body = runBody();
  setStatus("Queueing serial analysis...");
  clearProgress();
  el.resultActions.classList.add("hidden");
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
    renderProgress(job.progress);
    setStatus(jobStatusText(job));
    if (job.status === "done") {
      state.lastResult = job.result;
      setStatus(`Done: ${job.result.resultCount} cache(s), ${job.result.insertedFilters} filter insertion(s).`, "ok");
      clearProgress();
      state.currentJobId = "";
      el.cancelButton.classList.add("hidden");
      el.cancelButton.disabled = false;
      el.resultActions.classList.remove("hidden");
      updateRunState();
      return;
    }
    if (job.status === "error" || job.status === "cancelled") {
      setStatus(job.error || job.message || job.status, "error");
      clearProgress();
      state.currentJobId = "";
      el.cancelButton.classList.add("hidden");
      el.cancelButton.disabled = false;
      updateRunState();
      return;
    }
    setTimeout(pollJob, 1200);
  } catch (error) {
    setStatus(error.message, "error");
    clearProgress();
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
