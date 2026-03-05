#!/bin/bash
# Generates CHECKSUMS file for all distributable files
# Run this before committing changes to docs/aws/

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKSUMS_FILE="$REPO_ROOT/docs/aws/CHECKSUMS"

cd "$REPO_ROOT/docs/aws"

echo "# SHA256 checksums for NorthBuilt AWS Config Sync" > "$CHECKSUMS_FILE"
echo "# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$CHECKSUMS_FILE"
echo "# Verify with: shasum -a 256 -c CHECKSUMS" >> "$CHECKSUMS_FILE"
echo "" >> "$CHECKSUMS_FILE"

# Generate checksums for distributable files
for file in sync.sh aws-vault-1password aws-config; do
    if [ -f "$file" ]; then
        shasum -a 256 "$file" >> "$CHECKSUMS_FILE"
        echo "✓ $file"
    fi
done

echo ""
echo "Generated: $CHECKSUMS_FILE"
echo ""
cat "$CHECKSUMS_FILE"
