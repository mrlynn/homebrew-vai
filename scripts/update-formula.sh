#!/usr/bin/env bash
# update-formula.sh — Update the Homebrew formula to match the latest npm release
#
# This script is designed to be run from ANYWHERE — it clones/updates the tap
# repo automatically. No hardcoded versions. Everything is derived from npm.
#
# Usage:
#   ./scripts/update-formula.sh                    # Update to latest npm version
#   ./scripts/update-formula.sh --version 1.21.0   # Update to a specific version
#   ./scripts/update-formula.sh --push             # Update and push to GitHub
#   ./scripts/update-formula.sh --dry-run          # Show what would change
#
# Environment variables:
#   TAP_REPO       — Git remote for the tap (default: git@github.com:mrlynn/homebrew-vai.git)
#   TAP_DIR        — Local path to clone the tap into (default: /tmp/homebrew-vai)
#   NPM_PACKAGE    — npm package name (default: voyageai-cli)
#   FORMULA_NAME   — Formula filename without extension (default: vai)

set -euo pipefail

# ─── Configuration (all overridable via env vars) ────────────────────────────

TAP_REPO="${TAP_REPO:-git@github.com:mrlynn/homebrew-vai.git}"
TAP_DIR="${TAP_DIR:-/tmp/homebrew-vai}"
NPM_PACKAGE="${NPM_PACKAGE:-voyageai-cli}"
FORMULA_NAME="${FORMULA_NAME:-vai}"

# ─── Parse arguments ─────────────────────────────────────────────────────────

VERSION=""
PUSH=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)  VERSION="$2"; shift 2 ;;
    --push)     PUSH=true; shift ;;
    --dry-run)  DRY_RUN=true; shift ;;
    --help|-h)
      echo "Usage: $0 [--version X.Y.Z] [--push] [--dry-run]"
      echo ""
      echo "Options:"
      echo "  --version X.Y.Z   Update to a specific version (default: latest from npm)"
      echo "  --push            Commit and push changes to the tap repository"
      echo "  --dry-run         Show what would change without modifying anything"
      echo ""
      echo "Environment variables:"
      echo "  TAP_REPO          Git remote URL (default: git@github.com:mrlynn/homebrew-vai.git)"
      echo "  TAP_DIR           Local clone directory (default: /tmp/homebrew-vai)"
      echo "  NPM_PACKAGE       npm package name (default: voyageai-cli)"
      echo "  FORMULA_NAME      Formula file name (default: vai)"
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ─── Helper functions ────────────────────────────────────────────────────────

log()  { echo "==> $*"; }
info() { echo "    $*"; }
err()  { echo "ERROR: $*" >&2; exit 1; }

# Fetch a field from the npm registry JSON.
# Uses python3 first (most reliable), falls back to jq, then grep.
npm_field() {
  local url="$1"
  local field="$2"

  local json
  json=$(curl -sf "$url") || err "Failed to fetch $url"

  # Try python3 (available on macOS and most Linux)
  if command -v python3 &>/dev/null; then
    echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)${field})" 2>/dev/null && return
  fi

  # Try jq
  if command -v jq &>/dev/null; then
    echo "$json" | jq -r "$field" 2>/dev/null && return
  fi

  # Fallback: grep/sed (fragile but works for simple fields)
  local key
  key=$(echo "$field" | sed "s/.*'\([^']*\)'.*/\1/")
  echo "$json" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# ─── Step 1: Resolve version from npm ────────────────────────────────────────

log "Resolving version..."

NPM_REGISTRY_URL="https://registry.npmjs.org/${NPM_PACKAGE}/latest"

if [ -z "$VERSION" ]; then
  VERSION=$(npm_field "$NPM_REGISTRY_URL" "['version']")
fi

[ -z "$VERSION" ] && err "Could not determine version from npm registry"
info "Version: $VERSION"

# ─── Step 2: Get tarball URL and SHA256 ──────────────────────────────────────

log "Fetching tarball metadata..."

# The npm registry provides the tarball URL and shasum directly
TARBALL_URL=$(npm_field "$NPM_REGISTRY_URL" "['dist']['tarball']")
NPM_SHA=$(npm_field "$NPM_REGISTRY_URL" "['dist']['shasum']")

# If we couldn't get the tarball URL from the API, construct it
if [ -z "$TARBALL_URL" ]; then
  TARBALL_URL="https://registry.npmjs.org/${NPM_PACKAGE}/-/${NPM_PACKAGE}-${VERSION}.tgz"
fi

info "Tarball: $TARBALL_URL"

log "Computing SHA256 (downloading tarball)..."

# Download to a temp file so we can compute SHA256 and verify integrity
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

HTTP_STATUS=$(curl -sL -o "$TMPFILE" -w "%{http_code}" "$TARBALL_URL")

if [ "$HTTP_STATUS" != "200" ]; then
  err "Failed to download tarball (HTTP $HTTP_STATUS). Is version $VERSION published?"
fi

TARBALL_SIZE=$(wc -c < "$TMPFILE" | tr -d ' ')
if [ "$TARBALL_SIZE" -lt 1000 ]; then
  err "Downloaded tarball is suspiciously small ($TARBALL_SIZE bytes). Aborting."
fi

SHA256=$(shasum -a 256 "$TMPFILE" | awk '{print $1}')
info "SHA256:  $SHA256"
info "Size:    ${TARBALL_SIZE} bytes"

# ─── Step 3: Clone or update the tap repository ─────────────────────────────

log "Preparing tap repository..."

if [ -d "$TAP_DIR/.git" ]; then
  info "Updating existing clone at $TAP_DIR"
  git -C "$TAP_DIR" fetch origin
  git -C "$TAP_DIR" reset --hard origin/main 2>/dev/null || \
    git -C "$TAP_DIR" reset --hard origin/master
else
  info "Cloning $TAP_REPO to $TAP_DIR"
  rm -rf "$TAP_DIR"
  git clone "$TAP_REPO" "$TAP_DIR"
fi

FORMULA_PATH="$TAP_DIR/Formula/${FORMULA_NAME}.rb"

if [ ! -f "$FORMULA_PATH" ]; then
  err "Formula not found at $FORMULA_PATH"
fi

# ─── Step 4: Check if update is needed ───────────────────────────────────────

log "Checking current formula version..."

CURRENT_VERSION=$(sed -n "s/.*${NPM_PACKAGE}-\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\.tgz.*/\1/p" "$FORMULA_PATH" | head -1)
info "Current formula version: ${CURRENT_VERSION:-unknown}"
info "Target version:          $VERSION"

if [ "$CURRENT_VERSION" = "$VERSION" ]; then
  log "Formula is already at version $VERSION. Nothing to do."
  exit 0
fi

# ─── Step 5: Update the formula ──────────────────────────────────────────────

if [ "$DRY_RUN" = true ]; then
  log "[DRY RUN] Would update formula:"
  info "  URL:    $TARBALL_URL"
  info "  SHA256: $SHA256"
  info "  File:   $FORMULA_PATH"
  echo ""
  log "[DRY RUN] Diff preview:"

  # Create a temp copy to show the diff
  TMPFORMULA=$(mktemp)
  cp "$FORMULA_PATH" "$TMPFORMULA"
  sed -i '' "s|url \"https://registry.npmjs.org/${NPM_PACKAGE}/-/${NPM_PACKAGE}-.*\.tgz\"|url \"${TARBALL_URL}\"|" "$TMPFORMULA"
  sed -i '' "s|sha256 \".*\"|sha256 \"${SHA256}\"|" "$TMPFORMULA"
  diff --color=auto "$FORMULA_PATH" "$TMPFORMULA" || true
  rm -f "$TMPFORMULA"
  exit 0
fi

log "Updating formula..."

# Use sed to replace the url and sha256 lines
# This approach is resilient — it matches the pattern, not a specific version
sed -i '' "s|url \"https://registry.npmjs.org/${NPM_PACKAGE}/-/${NPM_PACKAGE}-.*\.tgz\"|url \"${TARBALL_URL}\"|" "$FORMULA_PATH"
sed -i '' "s|sha256 \".*\"|sha256 \"${SHA256}\"|" "$FORMULA_PATH"

info "Formula updated."

# ─── Step 6: Validate (if brew is available) ─────────────────────────────────

if command -v brew &>/dev/null; then
  log "Validating formula with Homebrew..."
  if brew audit --formula "$FORMULA_PATH" 2>&1; then
    info "Formula passes audit."
  else
    echo ""
    info "(Some audit warnings are expected for tap formulas — review above)"
  fi
else
  info "Homebrew not found — skipping formula validation."
  info "Run 'brew audit --strict Formula/${FORMULA_NAME}.rb' to validate manually."
fi

# ─── Step 7: Commit and push (if --push) ─────────────────────────────────────

if [ "$PUSH" = true ]; then
  log "Committing and pushing..."
  cd "$TAP_DIR"
  git add "Formula/${FORMULA_NAME}.rb"
  git commit -m "Update ${FORMULA_NAME} to ${VERSION}"
  git push origin HEAD
  info "Pushed to $TAP_REPO"
else
  log "Changes ready in $TAP_DIR"
  info "Review: cat $FORMULA_PATH"
  info "Push:   cd $TAP_DIR && git add -A && git commit -m 'Update ${FORMULA_NAME} to ${VERSION}' && git push"
  info "Or re-run with --push to commit and push automatically."
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
log "Done! Updated ${FORMULA_NAME} from ${CURRENT_VERSION:-unknown} → ${VERSION}"
echo ""
echo "  Users will receive the update on their next:"
echo "    brew update && brew upgrade ${FORMULA_NAME}"
echo ""
