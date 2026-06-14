#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

/usr/bin/swift "$ROOT_DIR/tests/ActiveLibrarySidebarResolverTests.swift"
