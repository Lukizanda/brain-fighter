"""
weapon_icon.py — one-command pipeline for weapon HUD icons.

Two subcommands:

  generate — produces a PNG on disk for a weapon
    --weapon Sword            (required; PascalCase, matches template folder)
    --fbx path/to/source.fbx  (required for --mode 3d)
    --mode {3d|meshy}         (default: 3d)
    --style "..."             (optional; only used for --mode meshy)

    Output: C:/Google Drive/Work/AI/Generated Icons/<Weapon>_<mode>.png

  publish — uploads a generated PNG to Roblox via Open Cloud and writes
    the WeaponIcon attribute into the weapon's template
    --weapon Sword            (required)
    --png path/to/icon.png    (optional; defaults to the generate output path)

    Uses the rbxthumb:// URL form because raw rbxassetid:// stalls on
    Open Cloud-uploaded Decals (see memory note).

Secrets loaded from .env at repo root: MESHY_API_KEY,
ROBLOX_OPEN_CLOUD_API_KEY, ROBLOX_USER_ID.

Zero third-party deps — uses stdlib only.
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

# ----------------------------------------------------------------------
# Paths + constants
# ----------------------------------------------------------------------

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT_DIR = pathlib.Path(r"C:/Google Drive/Work/AI/Generated Icons")
TEMPLATES_DIR = REPO_ROOT / "src" / "shared" / "Weapon" / "Templates"
DOTENV = REPO_ROOT / ".env"

MESHY_ENDPOINT = "https://api.meshy.ai/openapi/v1/image-to-image"
MESHY_POLL_INTERVAL = 5  # seconds
MESHY_POLL_MAX = 20

ROBLOX_UPLOAD_ENDPOINT = "https://apis.roblox.com/assets/v1/assets"
ROBLOX_OPERATION_ENDPOINT = "https://apis.roblox.com/assets/v1/operations/{op_id}"
ROBLOX_POLL_INTERVAL = 2
ROBLOX_POLL_MAX = 15

DEFAULT_STYLE_PROMPT = (
    "Bold cartoon game icon of a {weapon}, drawn to fill the entire "
    "image frame. COMPOSITION: the subject runs diagonally from the "
    "bottom-left corner to the top-right corner. Occupies approximately "
    "85 percent of the image dimension corner to corner — NO empty "
    "border or wasted space around the subject. STYLE: thick clean "
    "black outline around the full silhouette, cel-shaded with two "
    "flat tones per material. Hand-drawn cartoon style, simplified "
    "flat color planes, no gradients, no realistic rendering. "
    "Transparent background, no backdrop, no shadow."
)


# ----------------------------------------------------------------------
# Env + helpers
# ----------------------------------------------------------------------

def load_dotenv() -> dict:
    """Parse KEY=VALUE lines from repo-root .env. No quoting / no escaping."""
    env = {}
    if not DOTENV.is_file():
        return env
    for raw in DOTENV.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()
    return env


def require_env(env: dict, key: str) -> str:
    v = env.get(key)
    if not v or v.startswith("paste-"):
        raise SystemExit(f"Missing {key} in .env (got: {v!r})")
    return v


def print_step(msg: str) -> None:
    print(f"[weapon_icon] {msg}", flush=True)


def output_path_for(weapon: str, mode: str) -> pathlib.Path:
    return OUTPUT_DIR / f"{weapon}_{mode}.png"


def template_path_for(weapon: str) -> pathlib.Path:
    return TEMPLATES_DIR / weapon / "init.meta.json"


# ----------------------------------------------------------------------
# Subcommand: generate (3d mode — Blender hero render)
# ----------------------------------------------------------------------

def generate_3d(weapon: str, fbx: str, preset: str) -> pathlib.Path:
    """Run the existing Blender hero-icon renderer. Output goes to
    <OUTPUT_DIR>/<Weapon>_3d.png (matching the Blender script's naming).

    `preset` picks the camera angle tuned for the weapon silhouette —
    'sword' (top-down, diagonal) or 'gun' (3/4 side-profile)."""
    py_script = REPO_ROOT / "tools" / "render_weapon_hero_icon.py"
    blender = pathlib.Path(r"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe")
    if not blender.is_file():
        raise SystemExit(f"Blender not found at {blender}")
    print_step(f"rendering 3D hero icon via {py_script.name} (preset={preset})")

    fbx_path = str(pathlib.Path(fbx)).replace("\\", "/")
    result = subprocess.run(
        [str(blender), "--background", "--python", str(py_script), "--",
         weapon, fbx_path, preset],
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"Blender render failed (exit {result.returncode})")

    out = output_path_for(weapon, "3d")
    if not out.is_file():
        raise SystemExit(f"expected output at {out} but it's missing")
    print_step(f"wrote {out}")
    return out


# ----------------------------------------------------------------------
# Subcommand: generate (meshy mode — image-to-image)
# ----------------------------------------------------------------------

def meshy_generate(meshy_key: str, weapon: str, style_prompt: str) -> pathlib.Path:
    """Call Meshy Image-to-Image with the weapon's 3/4 reference render,
    poll until the task completes, download the result to disk."""
    ref_path = pathlib.Path(r"C:/Google Drive/Work/AI/icon_references") / weapon / "ThreeQuarter.png"
    if not ref_path.is_file():
        raise SystemExit(
            f"reference render missing at {ref_path}; run tools/render-icons.sh first "
            f"(add the weapon to tools/render_icon_references.py's WEAPONS list)"
        )

    b64 = base64.b64encode(ref_path.read_bytes()).decode("ascii")
    body = json.dumps({
        "ai_model": "nano-banana",
        "prompt": style_prompt,
        "reference_image_urls": [f"data:image/png;base64,{b64}"],
    }).encode("utf-8")

    req = urllib.request.Request(
        MESHY_ENDPOINT,
        data=body,
        headers={
            "Authorization": f"Bearer {meshy_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    print_step("submitting Meshy image-to-image task...")
    with urllib.request.urlopen(req) as resp:
        task_resp = json.loads(resp.read())
    task_id = task_resp.get("result")
    if not task_id:
        raise SystemExit(f"Meshy response missing 'result': {task_resp}")
    print_step(f"task {task_id} submitted, polling...")

    for attempt in range(1, MESHY_POLL_MAX + 1):
        poll_req = urllib.request.Request(
            f"{MESHY_ENDPOINT}/{task_id}",
            headers={"Authorization": f"Bearer {meshy_key}"},
        )
        with urllib.request.urlopen(poll_req) as resp:
            task = json.loads(resp.read())
        status = task.get("status")
        print_step(f"  attempt {attempt}: {status}")
        if status == "SUCCEEDED":
            url = task["image_urls"][0]
            break
        if status == "FAILED":
            raise SystemExit(f"Meshy task FAILED: {task}")
        time.sleep(MESHY_POLL_INTERVAL)
    else:
        raise SystemExit(f"Meshy task {task_id} didn't finish within "
                         f"{MESHY_POLL_MAX * MESHY_POLL_INTERVAL}s")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    out = output_path_for(weapon, "meshy")
    print_step(f"downloading result to {out}")
    with urllib.request.urlopen(url) as resp, out.open("wb") as f:
        f.write(resp.read())
    return out


# ----------------------------------------------------------------------
# Multipart form builder (for Roblox upload — stdlib has no helper)
# ----------------------------------------------------------------------

def build_multipart(fields: dict, files: dict) -> tuple[bytes, str]:
    """Encode a multipart/form-data body. `fields` is {name: (json_str, mime)};
    `files` is {name: (filepath, mime)}. Returns (body_bytes, content_type)."""
    boundary = f"----wiboundary{uuid.uuid4().hex}"
    parts = []
    for name, (value, mime) in fields.items():
        parts.append((
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{name}"\r\n'
            f"Content-Type: {mime}\r\n\r\n"
            f"{value}\r\n"
        ).encode("utf-8"))
    for name, (filepath, mime) in files.items():
        fname = pathlib.Path(filepath).name
        header = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{name}"; filename="{fname}"\r\n'
            f"Content-Type: {mime}\r\n\r\n"
        ).encode("utf-8")
        data = pathlib.Path(filepath).read_bytes()
        parts.append(header + data + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode("utf-8"))
    body = b"".join(parts)
    return body, f"multipart/form-data; boundary={boundary}"


# ----------------------------------------------------------------------
# Subcommand: publish (Roblox Open Cloud upload + template write)
# ----------------------------------------------------------------------

def roblox_upload_png(api_key: str, user_id: str, weapon: str, png: pathlib.Path) -> str:
    """Upload a PNG as a Decal via Open Cloud. Returns the asset ID string."""
    request_json = json.dumps({
        "assetType": "Decal",
        "displayName": f"{weapon}_icon",
        "description": f"HUD icon for {weapon} weapon (auto-uploaded via weapon_icon.py)",
        "creationContext": {"creator": {"userId": str(user_id)}},
    })
    body, content_type = build_multipart(
        fields={"request": (request_json, "application/json")},
        files={"fileContent": (str(png), "image/png")},
    )
    req = urllib.request.Request(
        ROBLOX_UPLOAD_ENDPOINT,
        data=body,
        headers={"x-api-key": api_key, "Content-Type": content_type},
        method="POST",
    )
    print_step(f"uploading {png.name} to Roblox Open Cloud...")
    with urllib.request.urlopen(req) as resp:
        op = json.loads(resp.read())
    op_id = op.get("operationId")
    if not op_id:
        raise SystemExit(f"upload response missing operationId: {op}")
    print_step(f"operation {op_id}, polling...")

    for attempt in range(1, ROBLOX_POLL_MAX + 1):
        poll_req = urllib.request.Request(
            ROBLOX_OPERATION_ENDPOINT.format(op_id=op_id),
            headers={"x-api-key": api_key},
        )
        with urllib.request.urlopen(poll_req) as resp:
            op = json.loads(resp.read())
        if op.get("done"):
            response = op.get("response", {})
            mod = response.get("moderationResult", {}).get("moderationState")
            asset_id = response.get("assetId")
            print_step(f"  attempt {attempt}: done — asset {asset_id}, moderation {mod}")
            if mod != "Approved":
                raise SystemExit(f"asset uploaded but moderation failed: {mod}")
            return str(asset_id)
        print_step(f"  attempt {attempt}: not done yet")
        time.sleep(ROBLOX_POLL_INTERVAL)
    raise SystemExit(f"operation {op_id} didn't finish within "
                     f"{ROBLOX_POLL_MAX * ROBLOX_POLL_INTERVAL}s")


def write_weapon_icon_to_template(weapon: str, asset_id: str) -> pathlib.Path:
    """Insert/update the `WeaponIcon` attribute in the weapon's init.meta.json.
    Uses rbxthumb:// URL form (see memory note: rbxassetid:// doesn't resolve
    reliably for Open Cloud uploads).

    Uses targeted text edits (regex) instead of full JSON round-trip so the
    original formatting — compact arrays, single-line attribute entries — is
    preserved byte-for-byte outside the WeaponIcon line itself.
    """
    template = template_path_for(weapon)
    if not template.is_file():
        raise SystemExit(f"template not found: {template}")

    text = template.read_text()
    icon_url = f"rbxthumb://type=Asset&id={asset_id}&w=420&h=420"
    new_entry = f'"WeaponIcon": {{ "String": "{icon_url}" }}'

    # Case 1: a WeaponIcon entry already exists — replace it in-place
    existing = re.search(r'"WeaponIcon":\s*\{\s*"String":\s*"[^"]*"\s*\}', text)
    if existing:
        text = text[:existing.start()] + new_entry + text[existing.end():]
    else:
        # Case 2: insert after WeaponCategory (always the last attribute in
        # templates that have been through the loadout-system migration).
        anchor = re.search(r'"WeaponCategory":\s*\{\s*"String":\s*"[^"]*"\s*\}', text)
        if not anchor:
            raise SystemExit(
                "couldn't find a WeaponCategory anchor to insert WeaponIcon after — "
                "does this weapon have its WeaponCategory attribute set?"
            )
        # Match the indentation of WeaponCategory so the new line aligns
        line_start = text.rfind("\n", 0, anchor.start()) + 1
        indent = text[line_start:anchor.start()]
        insertion = f",\n{indent}{new_entry}"
        text = text[:anchor.end()] + insertion + text[anchor.end():]

    template.write_text(text)
    print_step(f"wrote WeaponIcon into {template}")
    return template


# ----------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------

def cmd_generate(args, env):
    weapon = args.weapon
    mode = args.mode
    if mode == "3d":
        if not args.fbx:
            raise SystemExit("--fbx <path> is required for --mode 3d")
        generate_3d(weapon, args.fbx, args.preset)
    elif mode == "meshy":
        meshy_key = require_env(env, "MESHY_API_KEY")
        prompt = (args.style or DEFAULT_STYLE_PROMPT).replace("{weapon}", weapon)
        meshy_generate(meshy_key, weapon, prompt)
    else:
        raise SystemExit(f"unknown mode: {mode}")


def cmd_publish(args, env):
    api_key = require_env(env, "ROBLOX_OPEN_CLOUD_API_KEY")
    user_id = require_env(env, "ROBLOX_USER_ID")
    weapon = args.weapon
    if args.png:
        png = pathlib.Path(args.png)
    else:
        # Default: prefer 3d output, fall back to meshy
        png = output_path_for(weapon, "3d")
        if not png.is_file():
            png = output_path_for(weapon, "meshy")
    if not png.is_file():
        raise SystemExit(f"PNG not found at {png} (run `generate` first or pass --png)")

    asset_id = roblox_upload_png(api_key, user_id, weapon, png)
    write_weapon_icon_to_template(weapon, asset_id)
    print_step(f"done — {weapon} icon published as asset {asset_id}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    gen = sub.add_parser("generate", help="produce a PNG on disk for a weapon")
    gen.add_argument("--weapon", required=True)
    gen.add_argument("--mode", choices=("3d", "meshy"), default="3d")
    gen.add_argument("--fbx", default=None)
    gen.add_argument("--preset", choices=("sword", "gun"), default="sword",
                     help="camera preset for 3d mode — 'sword' (top-down diagonal) "
                          "or 'gun' (3/4 side profile)")
    gen.add_argument("--style", default=None,
                     help="style prompt override (meshy mode only)")

    pub = sub.add_parser("publish", help="upload a PNG and write the template")
    pub.add_argument("--weapon", required=True)
    pub.add_argument("--png", default=None,
                     help="path to PNG; defaults to <Weapon>_3d.png or <Weapon>_meshy.png")

    args = parser.parse_args()
    env = load_dotenv()

    if args.command == "generate":
        cmd_generate(args, env)
    elif args.command == "publish":
        cmd_publish(args, env)


if __name__ == "__main__":
    main()
