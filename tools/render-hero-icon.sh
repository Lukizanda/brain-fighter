#!/usr/bin/env bash
# render-hero-icon.sh — render a single hero 3/4 icon for one weapon.
# Used to produce 3D-rendered HUD icons directly (no Gemini/Meshy pass).
#
# Usage: tools/render-hero-icon.sh <weapon-name> <fbx-path> [preset]
#   preset: sword (default) | gun — picks camera angle tuned for the silhouette
#
# Output: C:/Google Drive/Work/AI/Generated Icons/<weapon-name>_3d.png

set -euo pipefail

BLENDER="/c/Program Files/Blender Foundation/Blender 5.1/blender.exe"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/render_weapon_hero_icon.py"

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <weapon-name> <fbx-path> [preset]" >&2
    exit 1
fi
if [[ ! -f "$2" ]]; then
    echo "fbx not found: $2" >&2
    exit 1
fi

"$BLENDER" --background --python "$PY_SCRIPT" -- "$1" "$2" "${3:-sword}"
