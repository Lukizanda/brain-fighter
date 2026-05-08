#!/usr/bin/env bash
# weapon-icon.sh — thin wrapper for tools/weapon_icon.py.
#
# Examples:
#   tools/weapon-icon.sh generate --weapon Sword --fbx path/to/sword.fbx
#   tools/weapon-icon.sh generate --weapon LaserPistol --mode meshy
#   tools/weapon-icon.sh publish  --weapon Sword

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python "$SCRIPT_DIR/weapon_icon.py" "$@"
