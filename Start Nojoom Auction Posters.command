#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app_path="$PWD/build/nojoom/Nojoom Auction Posters.app"
if [ ! -d "$app_path" ]; then
  ./desktop/scripts/build-mac.sh
fi
open "$app_path"
