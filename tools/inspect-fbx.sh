#!/usr/bin/env bash
# inspect-fbx.sh — render orthographic previews + report bbox for one or more FBX files
# via headless Blender. Used to figure out the right Euler before tools/prep-fbx.sh.
#
# Usage:
#   tools/inspect-fbx.sh <output_dir> <input1.fbx> [input2.fbx ...]
#
# Output: <output_dir>/<basename>/{bbox.json, view_pX.png, view_pY.png, view_pZ.png}

set -euo pipefail

BLENDER="/c/Program Files/Blender Foundation/Blender 5.1/blender.exe"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/inspect_fbx.py"

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <output_dir> <input1.fbx> [input2.fbx ...]" >&2
    exit 1
fi
if [[ ! -x "$BLENDER" ]]; then
    echo "Blender not at: $BLENDER" >&2
    exit 1
fi

output_dir="$1"; shift
mkdir -p "$output_dir"

"$BLENDER" --background --python "$PY_SCRIPT" -- "$output_dir" "$@"
echo "→ $output_dir"
