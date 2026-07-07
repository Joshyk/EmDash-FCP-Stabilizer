#!/usr/bin/env node
"use strict";

const path = require("path");
const { spawnSync } = require("child_process");

const serverDir = path.resolve(__dirname, "..");
const port = Number(process.env.STABILIZER_WEB_PORT || 3091);

function fail(message) {
  console.error(message);
  process.exit(1);
}

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.error) {
    fail(`Failed to run ${command}: ${result.error.message}`);
  }
  return result;
}

if (!Number.isInteger(port) || port <= 0 || port > 65535) {
  fail(`Invalid STABILIZER_WEB_PORT: ${process.env.STABILIZER_WEB_PORT}`);
}

function pidsFromLsofOutput(output) {
  return [...new Set(String(output || "")
    .split(/\r?\n/)
    .filter((line) => line.startsWith("p"))
    .map((line) => Number(line.slice(1)))
    .filter((pid) => Number.isInteger(pid) && pid > 0))];
}

const lsof = run("lsof", ["-nP", `-iTCP:${port}`, "-sTCP:LISTEN", "-Fp"]);
if (lsof.status !== 0) {
  console.log(`Stabilizer Event Analyzer web server is not listening on port ${port}.`);
  process.exit(0);
}

const pids = pidsFromLsofOutput(lsof.stdout);

if (pids.length === 0) {
  console.log(`Stabilizer Event Analyzer web server is not listening on port ${port}.`);
  process.exit(0);
}

function cwdForPid(pid) {
  const result = run("lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]);
  if (result.status !== 0) return "";
  const line = result.stdout.split(/\r?\n/).find((entry) => entry.startsWith("n"));
  return line ? line.slice(1) : "";
}

function commandForPid(pid) {
  const result = run("ps", ["-p", String(pid), "-o", "command="]);
  if (result.status !== 0) return "";
  return result.stdout.trim();
}

function isStabilizerNodeWebDir(cwd) {
  return cwd === serverDir || cwd.endsWith(`${path.sep}Stabilizer-Event-Analyzer${path.sep}node_web`);
}

function isStabilizerServerProcess(command, cwd) {
  return command.includes("node_web/server.js") ||
    (isStabilizerNodeWebDir(cwd) && /\bnode\b/.test(command) && /\bserver\.js\b/.test(command));
}

function splitTargets(candidatePids) {
  const foundTargets = [];
  const foundNonTargets = [];

  for (const pid of candidatePids) {
    const command = commandForPid(pid);
    const cwd = cwdForPid(pid);

    if (isStabilizerServerProcess(command, cwd)) {
      foundTargets.push({ pid, command, cwd });
    } else {
      foundNonTargets.push({ pid, command, cwd });
    }
  }

  return { foundTargets, foundNonTargets };
}

const { foundTargets: targets, foundNonTargets: nonTargets } = splitTargets(pids);

if (nonTargets.length > 0) {
  const details = nonTargets
    .map((item) => `pid ${item.pid}: ${item.command || "(unknown command)"} cwd=${item.cwd || "(unknown cwd)"}`)
    .join("\n");
  fail(`Port ${port} is not owned by the Stabilizer Event Analyzer web server; refusing to stop it.\n${details}`);
}

for (const target of targets) {
  console.log(`Stopping Stabilizer Event Analyzer web server on port ${port}: pid ${target.pid}`);
  try {
    process.kill(target.pid, "SIGTERM");
  } catch (error) {
    fail(`Failed to stop pid ${target.pid}: ${error.message}`);
  }
}

Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 1000);

const verify = run("lsof", ["-nP", `-iTCP:${port}`, "-sTCP:LISTEN", "-Fp"]);
if (verify.status === 0 && verify.stdout.trim()) {
  const remainingPids = pidsFromLsofOutput(verify.stdout);
  const { foundTargets: remainingTargets, foundNonTargets: remainingNonTargets } = splitTargets(remainingPids);
  if (remainingNonTargets.length > 0) {
    const details = remainingNonTargets
      .map((item) => `pid ${item.pid}: ${item.command || "(unknown command)"} cwd=${item.cwd || "(unknown cwd)"}`)
      .join("\n");
    fail(`Port ${port} is not owned by the Stabilizer Event Analyzer web server after SIGTERM; refusing to force-kill it.\n${details}`);
  }

  for (const target of remainingTargets) {
    console.log(`Force-stopping Stabilizer Event Analyzer web server on port ${port}: pid ${target.pid}`);
    try {
      process.kill(target.pid, "SIGKILL");
    } catch (error) {
      fail(`Failed to force-stop pid ${target.pid}: ${error.message}`);
    }
  }

  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 1000);

  const finalVerify = run("lsof", ["-nP", `-iTCP:${port}`, "-sTCP:LISTEN", "-Fp"]);
  if (finalVerify.status === 0 && finalVerify.stdout.trim()) {
    fail(`Stabilizer Event Analyzer web server did not stop after SIGKILL on port ${port}.`);
  }
}

console.log(`Stabilizer Event Analyzer web server stopped on port ${port}.`);
