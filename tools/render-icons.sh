#!/usr/bin/env bash
# render-icons.sh — render multi-angle reference PNGs for every weapon in
# tools/render_icon_references.py via headless Blender. Output goes to
# C:\Google Drive\Work\AI\icon_references\<WeaponName>\<Angle>.png.
#
# Usage: tools/render-icons.sh
#
# To add weapons, edit the WEAPONS list at the top of the Python script.

set -euo pipefail

BLENDER="/c/Program Files/Blender Foundation/Blender 5.1/blender.exe"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/render_icon_references.py"

if [[ ! -x "$BLENDER" ]]; then
    echo "Blender not at: $BLENDER" >&2
    exit 1
fi

"$BLENDER" --background --python "$PY_SCRIPT"
