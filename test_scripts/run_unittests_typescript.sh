#!/bin/bash
# Unit tests and static checks for a TypeScript (React + Vite) build folder.
# Usage: run_unittests_typescript.sh <build_folder>
# Exit codes: 0 pass; 1 usage; 2 filesystem; 69 toolchain missing; 80 only the static checks failed;
# any other non-zero code is the test command's own.

STATIC_CHECKS_FAILED=80

echo "===== [1/8] Toolchain check ====="
if ! command -v node >/dev/null 2>&1; then
  echo "Error: node is not installed (PATH=$PATH)."
  exit 69
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "Error: npm is not installed (PATH=$PATH)."
  exit 69
fi
echo "node $(node --version) at $(command -v node)"
echo "npm $(npm --version) at $(command -v npm)"

echo "===== [2/8] Argument validation ====="
if [ -z "$1" ]; then
  echo "Error: No build folder provided."
  echo "Usage: $0 <build_folder>"
  exit 1
fi
SOURCE_FOLDER="$1"
if [ ! -d "$SOURCE_FOLDER" ]; then
  echo "Error: Build folder '$SOURCE_FOLDER' does not exist."
  exit 2
fi
SOURCE_FOLDER="$(cd "$SOURCE_FOLDER" && pwd)"
echo "Source build folder: $SOURCE_FOLDER"

echo "===== [3/8] Working directory setup ====="
WORKING_FOLDER="/tmp/node_$(basename "$SOURCE_FOLDER")"
trap 'rm -rf "$WORKING_FOLDER"' EXIT
if [ -d "$WORKING_FOLDER" ]; then
  echo "Wiping existing working folder $WORKING_FOLDER"
  find "$WORKING_FOLDER" -mindepth 1 -exec rm -rf {} +
else
  echo "Creating working folder $WORKING_FOLDER"
  mkdir -p "$WORKING_FOLDER"
fi

echo "===== [4/8] Copy the build ====="
echo "+ cp -R $SOURCE_FOLDER/. $WORKING_FOLDER (excluding node_modules, dist)"
( cd "$SOURCE_FOLDER" && tar --exclude='./node_modules' --exclude='./dist' -cf - . ) | ( cd "$WORKING_FOLDER" && tar -xf - )
if [ $? -ne 0 ]; then
  echo "Error: copying $SOURCE_FOLDER to $WORKING_FOLDER failed."
  exit 2
fi

echo "===== [5/8] Enter the working directory ====="
echo "Moving to: $WORKING_FOLDER"
cd "$WORKING_FOLDER" 2>/dev/null || { echo "Error: cannot enter $WORKING_FOLDER."; exit 2; }
echo "Now in $(pwd)"

echo "===== [6/8] Install dependencies into ./node_modules ====="
if [ ! -f package.json ]; then
  echo "Error: no package.json in $(pwd) - nothing to install or test."
  exit 1
fi
if [ -f package-lock.json ]; then
  echo "+ npm ci --no-audit --no-fund (from $(pwd)/package-lock.json)"
  npm ci --no-audit --no-fund
else
  echo "+ npm install --no-audit --no-fund (no package-lock.json in $(pwd))"
  npm install --no-audit --no-fund
fi
INSTALL=$?
if [ "$INSTALL" -ne 0 ]; then
  echo "Error: dependency install failed with exit $INSTALL in $(pwd)."
  exit "$INSTALL"
fi
BIN="$(pwd)/node_modules/.bin"
echo "Tools resolve from $BIN"

echo "===== [7/8] Static checks ====="
CHECKS=0
run_check() {
  local name="$1"; shift
  local tool="$1"
  if [ ! -x "$BIN/$tool" ]; then
    echo "package.json:1:1: $tool is not in devDependencies - add it"
    CHECKS=1
    return
  fi
  echo "+ $*"
  "$BIN/$@"
  local code=$?
  if [ "$code" -ne 0 ]; then
    echo "$name: FAILED (exit $code)"
    CHECKS=1
  else
    echo "$name: passed"
  fi
}
run_check "format" prettier --list-different --ignore-unknown .
run_check "lint" eslint --max-warnings 0 .
if [ -x "$BIN/vue-tsc" ]; then
  run_check "typecheck" vue-tsc --noEmit --pretty false
elif grep -q '"references"' tsconfig.json 2>/dev/null; then
  run_check "typecheck" tsc --build --pretty false
else
  run_check "typecheck" tsc --noEmit --pretty false
fi
[ "$CHECKS" -eq 0 ] && echo "Static checks: passed" || echo "Static checks: FAILED - the findings are above"

echo "===== [8/8] Unit tests ====="
if [ ! -x "$BIN/vitest" ]; then
  echo "Error: vitest is not in devDependencies (looked in $BIN)."
  TESTS=1
else
  echo "+ $BIN/vitest run (cwd $(pwd))"
  "$BIN/vitest" run
  TESTS=$?
fi

if [ "$TESTS" -ne 0 ]; then
  STATUS=$TESTS
elif [ "$CHECKS" -ne 0 ]; then
  STATUS=$STATIC_CHECKS_FAILED
else
  STATUS=0
fi
echo "static checks: $([ "$CHECKS" -eq 0 ] && echo passed || echo failed); unit tests (vitest run): exit $TESTS; exit $STATUS (working folder $WORKING_FOLDER)"
exit "$STATUS"
