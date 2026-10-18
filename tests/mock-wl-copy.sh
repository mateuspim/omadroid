#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == --type && "${2:-}" == text/plain ]] || exit 2
cat > "$OMADROID_CLIPBOARD_LOG"
