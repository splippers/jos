#!/bin/bash
set -euo pipefail
# Print the JOS brand block from the repository. Developer helper: the initrd
# uses build/jos-banner.sh, which reads /etc/jos-version and /etc/jos-logo.txt.
#
#   ./build/jos-branding.sh
#   ./build/jos-branding.sh --plain   # no tagline

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(cat "$HERE/../VERSION" 2>/dev/null || echo unknown)"

cat "$HERE/../branding/jos-logo.txt"
printf '\n  JOS - Jonathan'\''s OS  %s\n' "$VERSION"

if [[ "${1:-}" != "--plain" ]]; then
  printf '  Secure Boot imaging runtime for FOG\n'
fi
