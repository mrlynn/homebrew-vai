#!/usr/bin/env bash
# postpublish.sh — npm lifecycle hook to update the Homebrew formula
#
# Add to your package.json scripts:
#   "postpublish": "./scripts/postpublish.sh"
#
# This runs automatically after every `npm publish`. It:
#   1. Waits briefly for npm registry propagation
#   2. Calls update-formula.sh with the just-published version
#   3. Optionally pushes the tap update (controlled by env var)
#
# Environment variables:
#   HOMEBREW_AUTO_PUSH   — Set to "true" to auto-push (default: false)
#   SKIP_HOMEBREW_UPDATE — Set to "true" to skip entirely

set -euo pipefail

# Allow skipping entirely (useful in CI where you handle it differently)
if [ "${SKIP_HOMEBREW_UPDATE:-false}" = "true" ]; then
  echo "Skipping Homebrew formula update (SKIP_HOMEBREW_UPDATE=true)"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE_SCRIPT="$SCRIPT_DIR/update-formula.sh"

if [ ! -f "$UPDATE_SCRIPT" ]; then
  echo "Warning: update-formula.sh not found at $UPDATE_SCRIPT"
  echo "Skipping Homebrew formula update."
  exit 0
fi

# Get the version that was just published from package.json
VERSION=$(node -p "require('./package.json').version")

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Updating Homebrew formula for vai v${VERSION}       ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# Wait a moment for npm registry to propagate
echo "Waiting 10s for npm registry propagation..."
sleep 10

# Build the arguments
ARGS=("--version" "$VERSION")

if [ "${HOMEBREW_AUTO_PUSH:-false}" = "true" ]; then
  ARGS+=("--push")
fi

# Run the update script — don't fail the publish if this fails
if bash "$UPDATE_SCRIPT" "${ARGS[@]}"; then
  echo ""
  echo "Homebrew formula updated successfully."
else
  echo ""
  echo "Warning: Homebrew formula update failed. You can update manually:"
  echo "  ./scripts/update-formula.sh --version $VERSION --push"
fi
