#!/usr/bin/env node
"use strict";

const http = require("http");

const HOST = process.env.STABILIZER_WEB_HOST || "127.0.0.1";
const PORT = Number(process.env.STABILIZER_WEB_PORT || 3091);

const req = http.request(
  { host: HOST, port: PORT, path: "/api/shutdown", method: "POST" },
  (res) => {
    res.resume();
    res.on("end", () => process.exit(res.statusCode === 200 ? 0 : 1));
  }
);
req.on("error", (error) => {
  console.error(error.message);
  process.exit(1);
});
req.end();
