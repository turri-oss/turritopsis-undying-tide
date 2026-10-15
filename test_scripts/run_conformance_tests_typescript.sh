#!/bin/bash
# Conformance tests (Playwright + Chromium) for a TypeScript React + Vite build.
# Usage: run_conformance_tests_typescript.sh <build_folder> <conformance_tests_folder>
# The build is staged into /tmp/node_conformance_<basename of build>, built and served there with
# `npm run build` and `npm run preview -- --port $PORT`; the tests are read in place from the tests folder.
# Exit codes: 0 pass; 1 no tests discovered / tests in the build folder; 69 usage or environment;
# 80 the suite passed and only the static checks of the tests failed; else the test command's own code.

UNRECOVERABLE_ERROR_EXIT_CODE=69
STATIC_CHECKS_FAILED=80
INVOCATION_DIR="$(pwd)"

echo "===== [1/9] Toolchain check ====="
for tool in node npm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: $tool is not installed (PATH=$PATH)."
    exit $UNRECOVERABLE_ERROR_EXIT_CODE
  fi
done
echo "node $(node --version) at $(command -v node)"
echo "npm $(npm --version) at $(command -v npm)"

echo "===== [2/9] Argument validation ====="
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Error: both a build folder and a conformance tests folder are required."
  echo "Usage: $0 <build_folder> <conformance_tests_folder>"
  exit $UNRECOVERABLE_ERROR_EXIT_CODE
fi
if [ ! -d "$1" ]; then
  echo "Error: build folder '$1' does not exist."
  exit $UNRECOVERABLE_ERROR_EXIT_CODE
fi
BUILD_FOLDER="$(cd "$1" && pwd)"

echo "===== [3/9] Resolve the conformance tests folder ====="
case "$2" in
  /*) CONFORMANCE_TESTS_FOLDER="$2" ;;
  *)  CONFORMANCE_TESTS_FOLDER="$INVOCATION_DIR/$2" ;;
esac
if [ ! -d "$CONFORMANCE_TESTS_FOLDER" ]; then
  echo "Error: conformance tests folder '$CONFORMANCE_TESTS_FOLDER' does not exist."
  exit $UNRECOVERABLE_ERROR_EXIT_CODE
fi
CONFORMANCE_TESTS_FOLDER="$(cd "$CONFORMANCE_TESTS_FOLDER" && pwd)"
echo "Build folder:             $BUILD_FOLDER"
echo "Conformance tests folder: $CONFORMANCE_TESTS_FOLDER"

echo "===== [4/9] Working directory setup ====="
WORKING_FOLDER="/tmp/node_conformance_$(basename "$BUILD_FOLDER")"
trap 'rm -rf "$WORKING_FOLDER"' EXIT
rm -rf "$WORKING_FOLDER"
mkdir -p "$WORKING_FOLDER" || exit $UNRECOVERABLE_ERROR_EXIT_CODE
echo "Working folder: $WORKING_FOLDER"

echo "===== [4b/9] Refuse conformance tests in the build folder ====="
MISPLACED=$( (grep -rlE --exclude=".turri*" --exclude-dir=node_modules --exclude-dir=dist \
    "conformance tests of (functionality [0-9]|the spec)|acceptance test [0-9]+ of functionality" "$BUILD_FOLDER" 2>/dev/null; \
  find "$BUILD_FOLDER" -type f \( -ipath "*conformance*" -o -ipath "*acceptance*" \) -iname "*test*" \
    -not -name ".turri*" -not -path "*/node_modules/*" -not -path "*/dist/*" 2>/dev/null) | sort -u)
if [ -n "$MISPLACED" ]; then
  printf "Error: conformance tests found in the build folder %s - they belong in the conformance tests folder %s:\n%s\n" \
    "$BUILD_FOLDER" "$CONFORMANCE_TESTS_FOLDER" "$MISPLACED" >&2
  exit 1
fi
echo "None found."

echo "===== [5/9] Copy the build (without node_modules, dist) ====="
( cd "$BUILD_FOLDER" && tar --exclude='./node_modules' --exclude='./dist' -cf - . ) | ( cd "$WORKING_FOLDER" && tar -xf - )
if [ $? -ne 0 ]; then
  echo "Error: copying $BUILD_FOLDER to $WORKING_FOLDER failed."
  exit $UNRECOVERABLE_ERROR_EXIT_CODE
fi

echo "===== [6/9] Enter the working directory ====="
echo "Moving to: $WORKING_FOLDER"
cd "$WORKING_FOLDER" 2>/dev/null
if [ $? -ne 0 ]; then
  echo "Error: cannot enter $WORKING_FOLDER."
  exit $UNRECOVERABLE_ERROR_EXIT_CODE
fi

echo "===== [7/9] Install dependencies into ./node_modules ====="
start_time=$(date +%s)
if [ ! -f package.json ]; then
  echo "Error: no package.json in the build - nothing to build or serve."
  exit $UNRECOVERABLE_ERROR_EXIT_CODE
fi
if [ -f package-lock.json ]; then
  echo "+ npm ci --no-audit --no-fund"
  npm ci --no-audit --no-fund || exit $?
else
  echo "+ npm install --no-audit --no-fund"
  npm install --no-audit --no-fund || exit $?
fi
# What the tests and their checks need, beside the build's own dependencies, when the build lacks it.
EXTRA=""
for pkg in @playwright/test @types/node typescript typescript-eslint eslint prettier; do
  [ -d "node_modules/$pkg" ] || EXTRA="$EXTRA $pkg"
done
if [ -n "$EXTRA" ]; then
  echo "+ npm install --no-save --no-audit --no-fund$EXTRA"
  # shellcheck disable=SC2086
  npm install --no-save --no-audit --no-fund $EXTRA || exit $?
fi
BIN="$WORKING_FOLDER/node_modules/.bin"
# Chromium goes to Playwright's shared browser cache on this machine (PLAYWRIGHT_BROWSERS_PATH, if set), not re-downloaded per run.
echo "+ $BIN/playwright install chromium"
"$BIN/playwright" install chromium || exit $UNRECOVERABLE_ERROR_EXIT_CODE
echo "Requirements setup completed in $(( $(date +%s) - start_time )) seconds"
echo "Playwright: $("$BIN/playwright" --version)"

# The tests import @playwright/test from the tests folder, which has no node_modules of its own.
export NODE_PATH="$WORKING_FOLDER/node_modules"
# A read-only view of the tests inside the working folder, so ESLint and tsc see them under their base path.
ln -sfn "$CONFORMANCE_TESTS_FOLDER" "$WORKING_FOLDER/conformance"

echo "===== [7b/9] Static checks of the conformance tests ====="
cat > conformance.eslint.config.mjs <<'EOF'
import tseslint from 'typescript-eslint';
export default tseslint.config({ files: ['conformance/**/*.ts'], extends: [...tseslint.configs.recommended] });
EOF
cat > tsconfig.conformance.json <<'EOF'
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noEmit": true,
    "target": "ES2022",
    "lib": ["ES2022", "DOM"],
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "skipLibCheck": true,
    "preserveSymlinks": true,
    "types": ["node"]
  },
  "include": ["conformance/**/*.ts"]
}
EOF
CHECKS=0
echo "+ prettier --check --no-config --ignore-path /dev/null $CONFORMANCE_TESTS_FOLDER"
"$BIN/prettier" --check --no-config --ignore-path /dev/null "$CONFORMANCE_TESTS_FOLDER" || CHECKS=1
echo "+ eslint --no-config-lookup -c conformance.eslint.config.mjs --max-warnings 0 conformance/"
"$BIN/eslint" --no-config-lookup -c conformance.eslint.config.mjs --max-warnings 0 conformance/ || CHECKS=1
echo "+ tsc -p tsconfig.conformance.json --pretty false"
"$BIN/tsc" -p tsconfig.conformance.json --pretty false || CHECKS=1
[ "$CHECKS" -eq 0 ] && echo "Static checks: passed" || echo "Static checks: FAILED - the findings are above"

echo "===== [8/9] Run the conformance suite ====="
PORT=$(node -e 'const s=require("net").createServer();s.listen(0,()=>{console.log(s.address().port);s.close();});')
export PORT
echo "Serving the build on port $PORT"
cat > playwright.conformance.config.mjs <<EOF
import { defineConfig, devices } from '@playwright/test';
export default defineConfig({
  testDir: '$CONFORMANCE_TESTS_FOLDER',
  testMatch: '**/*.@(spec|test).ts',
  outputDir: '$WORKING_FOLDER/test-results',
  forbidOnly: true,
  retries: 0,
  workers: 1,
  reporter: [['list']],
  use: { baseURL: 'http://localhost:$PORT', trace: 'off' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'], viewport: { width: 1280, height: 720 } } }],
  webServer: {
    command: 'npm run build && npm run preview -- --port $PORT --strictPort',
    url: 'http://localhost:$PORT',
    reuseExistingServer: false,
    timeout: 180000,
  },
});
EOF
TEST_CMD="$BIN/playwright test -c playwright.conformance.config.mjs"
echo "+ $TEST_CMD (cwd $(pwd), NODE_PATH=$NODE_PATH)"
output=$($TEST_CMD 2>&1)
exit_code=$?
echo "$output"

if echo "$output" | grep -qE "No tests found|Total: 0 tests"; then
  echo "Error: no conformance tests discovered in $CONFORMANCE_TESTS_FOLDER."
  exit 1
fi

echo "===== [9/9] Result ====="
if [ "$exit_code" -ne 0 ]; then
  STATUS=$exit_code
elif [ "$CHECKS" -ne 0 ]; then
  echo "The conformance tests pass, and their static checks do not."
  STATUS=$STATIC_CHECKS_FAILED
else
  STATUS=0
fi
echo "test command: $TEST_CMD; exit $STATUS; tests $CONFORMANCE_TESTS_FOLDER; working folder $WORKING_FOLDER"
exit "$STATUS"
