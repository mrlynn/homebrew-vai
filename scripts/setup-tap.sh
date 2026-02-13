#!/usr/bin/env bash
# setup-tap.sh — Bootstrap and update the Homebrew tap for vai
#
# This script handles BOTH initial setup and ongoing updates.
# It creates the proper directory structure if it doesn't exist,
# finds the formula file wherever it lives, and updates it with
# the correct version and SHA256 from npm.
#
# Usage:
#   sh setup-tap.sh                          # Update to latest npm version
#   sh setup-tap.sh --version 1.27.0         # Update to a specific version
#   sh setup-tap.sh --push                   # Update and push to GitHub
#   sh setup-tap.sh --dry-run                # Show what would change
#   sh setup-tap.sh --init                   # Just create directory structure
#
# Run from anywhere — it figures out where it is and sets up the
# correct Homebrew tap layout relative to its own location.

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

NPM_PACKAGE="voyageai-cli"
FORMULA_NAME="vai"
TAP_REPO_REMOTE="git@github.com:mrlynn/homebrew-vai.git"

# ─── Parse arguments ─────────────────────────────────────────────────────────

VERSION=""
PUSH=false
DRY_RUN=false
INIT_ONLY=false

while [ $# -gt 0 ]; do
  case "$1" in
    --version)  VERSION="$2"; shift 2 ;;
    --push)     PUSH=true; shift ;;
    --dry-run)  DRY_RUN=true; shift ;;
    --init)     INIT_ONLY=true; shift ;;
    --help|-h)
      echo "Usage: $0 [--version X.Y.Z] [--push] [--dry-run] [--init]"
      echo ""
      echo "  --version X.Y.Z   Target version (default: latest from npm)"
      echo "  --push             Commit and push to GitHub after update"
      echo "  --dry-run          Preview changes without modifying files"
      echo "  --init             Just set up directory structure, skip npm update"
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ─── Helpers ─────────────────────────────────────────────────────────────────

log()  { echo "==> $*"; }
info() { echo "    $*"; }
err()  { echo "ERROR: $*" >&2; exit 1; }

# ─── Locate the tap root directory ───────────────────────────────────────────
# The tap root is the directory that contains (or will contain) Formula/vai.rb.
# We walk up from wherever this script lives until we find a directory that
# looks like a tap root, or we use the script's parent directory.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check if we're already in a proper tap structure
find_tap_root() {
  local dir="$1"

  # Walk up to 3 levels looking for Formula/vai.rb
  for _ in 1 2 3; do
    if [ -f "$dir/Formula/${FORMULA_NAME}.rb" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  # Not found — check if vai.rb exists in the current directory or script dir
  if [ -f "${SCRIPT_DIR}/${FORMULA_NAME}.rb" ]; then
    # Formula is flat in the same directory as this script — use parent as root
    echo "$(dirname "$SCRIPT_DIR")"
    return 1  # signal that we need to restructure
  elif [ -f "./${FORMULA_NAME}.rb" ]; then
    echo "$(dirname "$(pwd)")"
    return 1
  fi

  # Nothing found — use script dir as the root and we'll create everything
  echo "$SCRIPT_DIR"
  return 1
}

TAP_ROOT=""
NEEDS_RESTRUCTURE=false

if TAP_ROOT=$(find_tap_root "$SCRIPT_DIR"); then
  log "Found tap root: $TAP_ROOT"
else
  NEEDS_RESTRUCTURE=true
  # If vai.rb is in the same directory as this script, root is one level up
  if [ -f "${SCRIPT_DIR}/${FORMULA_NAME}.rb" ]; then
    TAP_ROOT="$(dirname "$SCRIPT_DIR")"
  else
    TAP_ROOT="$SCRIPT_DIR"
  fi
  log "Tap root: $TAP_ROOT (needs restructuring)"
fi

# ─── Create / fix directory structure ────────────────────────────────────────

log "Setting up directory structure..."

FORMULA_DIR="$TAP_ROOT/Formula"
SCRIPTS_DIR="$TAP_ROOT/scripts"
WORKFLOWS_DIR="$TAP_ROOT/.github/workflows"
FORMULA_PATH="$FORMULA_DIR/${FORMULA_NAME}.rb"

mkdir -p "$FORMULA_DIR" "$SCRIPTS_DIR" "$WORKFLOWS_DIR"

# Move vai.rb into Formula/ if it exists elsewhere
if [ "$NEEDS_RESTRUCTURE" = true ]; then
  # Check various locations where vai.rb might be
  for candidate in \
    "${SCRIPT_DIR}/${FORMULA_NAME}.rb" \
    "${TAP_ROOT}/${FORMULA_NAME}.rb" \
    "./${FORMULA_NAME}.rb"; do
    if [ -f "$candidate" ] && [ ! -f "$FORMULA_PATH" ]; then
      info "Moving $(basename "$candidate") → Formula/${FORMULA_NAME}.rb"
      mv "$candidate" "$FORMULA_PATH"
      break
    fi
  done
fi

# Move other files into their proper locations if they're in the wrong place
for file in update-formula.sh postpublish.sh; do
  for candidate in "${SCRIPT_DIR}/$file" "${TAP_ROOT}/$file" "./$file"; do
    if [ -f "$candidate" ] && [ ! -f "$SCRIPTS_DIR/$file" ]; then
      info "Moving $file → scripts/$file"
      cp "$candidate" "$SCRIPTS_DIR/$file"
      chmod +x "$SCRIPTS_DIR/$file"
      # Don't delete the original if it's in the same dir as this script
      break
    fi
  done
done

for file in update-formula.yml; do
  for candidate in "${SCRIPT_DIR}/$file" "${TAP_ROOT}/$file" "./$file"; do
    if [ -f "$candidate" ] && [ ! -f "$WORKFLOWS_DIR/$file" ]; then
      info "Moving $file → .github/workflows/$file"
      cp "$candidate" "$WORKFLOWS_DIR/$file"
      break
    fi
  done
done

# Move README.md to root if needed
for candidate in "${SCRIPT_DIR}/README.md" "./${SCRIPT_DIR}/README.md"; do
  if [ -f "$candidate" ] && [ ! -f "$TAP_ROOT/README.md" ]; then
    info "Moving README.md → tap root"
    cp "$candidate" "$TAP_ROOT/README.md"
    break
  fi
done

# Move this setup script into scripts/ if it's not already there
if [ "$SCRIPT_DIR" != "$SCRIPTS_DIR" ] && [ ! -f "$SCRIPTS_DIR/setup-tap.sh" ]; then
  info "Copying setup-tap.sh → scripts/setup-tap.sh"
  cp "$0" "$SCRIPTS_DIR/setup-tap.sh"
  chmod +x "$SCRIPTS_DIR/setup-tap.sh"
fi

# Verify the formula file exists
if [ ! -f "$FORMULA_PATH" ]; then
  err "Could not find or create Formula/${FORMULA_NAME}.rb
       
  Make sure vai.rb is in the same directory as this script,
  or in the Formula/ subdirectory."
fi

info "Formula: $FORMULA_PATH"

# Print the resulting structure
log "Tap structure:"
echo ""
(cd "$TAP_ROOT" && find . -not -path './.git/*' -not -path './.git' -not -name '*.bak' | sort | head -20 | sed 's|^|    |')
echo ""

if [ "$INIT_ONLY" = true ]; then
  log "Directory structure ready. Run without --init to update the formula."
  exit 0
fi

# ─── Resolve version from npm ────────────────────────────────────────────────

log "Resolving version from npm..."

NPM_URL="https://registry.npmjs.org/${NPM_PACKAGE}/latest"

if [ -z "$VERSION" ]; then
  # Try python3 first, then jq, then grep — at least one will work
  NPM_JSON=$(curl -sf "$NPM_URL") || err "Failed to fetch npm registry"

  VERSION=$(echo "$NPM_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])" 2>/dev/null) || \
  VERSION=$(echo "$NPM_JSON" | jq -r '.version' 2>/dev/null) || \
  VERSION=$(echo "$NPM_JSON" | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4) || \
  err "Could not parse version from npm"
fi

info "Version: $VERSION"

# ─── Check if update is needed ───────────────────────────────────────────────

CURRENT_VERSION=$(grep -o "${NPM_PACKAGE}-[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*" "$FORMULA_PATH" | head -1 | sed "s/${NPM_PACKAGE}-//")
info "Current formula: ${CURRENT_VERSION:-not set / placeholder}"

if [ "$CURRENT_VERSION" = "$VERSION" ]; then
  log "Formula is already at version $VERSION. Nothing to do."
  exit 0
fi

# ─── Download tarball and compute SHA256 ─────────────────────────────────────

TARBALL_URL="https://registry.npmjs.org/${NPM_PACKAGE}/-/${NPM_PACKAGE}-${VERSION}.tgz"

log "Downloading tarball..."
info "URL: $TARBALL_URL"

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

HTTP_CODE=$(curl -sL -o "$TMPFILE" -w "%{http_code}" "$TARBALL_URL")

if [ "$HTTP_CODE" != "200" ]; then
  err "Download failed (HTTP $HTTP_CODE). Is version $VERSION published on npm?"
fi

# Sanity check
FILESIZE=$(wc -c < "$TMPFILE" | tr -d ' ')
if [ "$FILESIZE" -lt 1000 ]; then
  err "Tarball is only $FILESIZE bytes — something went wrong."
fi

SHA256=$(shasum -a 256 "$TMPFILE" | awk '{print $1}')
info "SHA256: $SHA256"
info "Size:   $FILESIZE bytes"

# ─── Update the formula ─────────────────────────────────────────────────────

if [ "$DRY_RUN" = true ]; then
  log "[DRY RUN] Would update:"
  info "  URL:    $TARBALL_URL"
  info "  SHA256: $SHA256"
  echo ""
  exit 0
fi

log "Updating formula..."

# Pattern-based sed — matches any version, not a specific one
sed -i.bak "s|url \"https://registry.npmjs.org/${NPM_PACKAGE}/-/${NPM_PACKAGE}-.*\.tgz\"|url \"${TARBALL_URL}\"|" "$FORMULA_PATH"
sed -i.bak "s|sha256 \"[^\"]*\"|sha256 \"${SHA256}\"|" "$FORMULA_PATH"
rm -f "${FORMULA_PATH}.bak"

info "Formula updated."

# Verify the update took effect
VERIFY_SHA=$(grep -o 'sha256 "[a-f0-9]*"' "$FORMULA_PATH" | grep -o '[a-f0-9]\{64\}')
if [ "$VERIFY_SHA" != "$SHA256" ]; then
  err "Verification failed — SHA256 in formula doesn't match expected value"
fi
info "Verified ✓"

# ─── Validate if brew is available ───────────────────────────────────────────

if command -v brew >/dev/null 2>&1; then
  log "Running brew audit..."
  brew audit --formula "$FORMULA_PATH" 2>&1 || info "(Some audit warnings are normal for tap formulas)"
fi

# ─── Commit and push ─────────────────────────────────────────────────────────

if [ "$PUSH" = true ]; then
  log "Committing and pushing..."
  cd "$TAP_ROOT"

  # Initialize git if this is a fresh setup
  if [ ! -d .git ]; then
    git init
    git remote add origin "$TAP_REPO_REMOTE" 2>/dev/null || true
  fi

  git add -A
  git commit -m "Update ${FORMULA_NAME} to ${VERSION}"
  git push origin HEAD
  info "Pushed to $TAP_REPO_REMOTE"
else
  echo ""
  log "Ready! Next steps:"
  echo ""
  echo "  Review:  cat $FORMULA_PATH"
  echo "  Push:    cd $TAP_ROOT && git add -A && git commit -m 'Update vai to ${VERSION}' && git push"
  echo "  Or:      sh $0 --push"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
log "✓ Updated vai: ${CURRENT_VERSION:-placeholder} → ${VERSION}"
echo ""
echo "  Users install/upgrade with:"
echo "    brew tap mrlynn/vai"
echo "    brew install vai"
echo ""
