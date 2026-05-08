#!/usr/bin/env bash
# prep-fbx.sh — rotate/scale an FBX to Roblox conventions via headless Blender.
#
# Produces a `<name>_roblox.fbx` that works for both Studio's Import 3D
# and the Open Cloud Model upload (tools/weapon_mesh.py). Textures are
# embedded so Studio doesn't stall on "skin paths can't be read", and
# stray armature/skin bindings are stripped before re-export.
#
# Usage:
#   tools/prep-fbx.sh input.fbx                         # default: rotate 0 0 90, scale 0.015 (tuned for Meshy)
#   tools/prep-fbx.sh input.fbx 0 0 90                  # custom Euler (degrees), scale stays default
#   tools/prep-fbx.sh input.fbx 0 0 0 --scale 1.0       # skip all transforms
#   tools/prep-fbx.sh input.fbx -90 90 0 --scale 0.02   # rotation + custom scale
#
# Output: input_roblox.fbx next to the source file.

set -euo pipefail

BLENDER="/c/Program Files/Blender Foundation/Blender 5.1/blender.exe"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/fbx_reorient.py"

if [[ $# -lt 1 ]]; then
    echo "usage: $0 input.fbx [rx ry rz] [--scale F]" >&2
    exit 1
fi
if [[ ! -f "$1" ]]; then
    echo "not found: $1" >&2
    exit 1
fi
if [[ ! -x "$BLENDER" ]]; then
    echo "Blender not at: $BLENDER" >&2
    exit 1
fi

input="$1"; shift
base="${input%.fbx}"
output="${base}_roblox.fbx"

"$BLENDER" --background --python "$PY_SCRIPT" -- "$input" "$output" "$@"
echo "→ $output"
