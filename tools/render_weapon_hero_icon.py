"""
render_weapon_hero_icon.py — Blender headless.

Renders a single hero 3/4 icon for one weapon, intended to be used as
the HUD icon directly (no Gemini/Meshy pass in between). Output is a
1024×1024 PNG with transparent background, tighter framing than the
reference renders, with dramatic 3-point lighting for depth.

Usage (via the tools/render-hero-icon.sh wrapper):
    tools/render-hero-icon.sh <weapon-name> <fbx-path>

Output:
    C:/Google Drive/Work/AI/Generated Icons/<weapon-name>_3d.png
"""

from __future__ import annotations

import math
import os
import sys
from typing import Tuple

import bpy
import mathutils


OUTPUT_DIR = r"C:\Google Drive\Work\AI\Generated Icons"
RESOLUTION = 1024

# Default framing multiplier against the bounding-box max dimension.
# Smaller = tighter crop. Per-preset override via "padding" field below.
# Sword can sit near 0.85 because it's a thin diagonal; gun needs room
# because its cross-axis (grip, optic) sticks out of the long axis.
FRAMING_PADDING = 0.85


def parse_args() -> Tuple[str, str, str]:
    if "--" not in sys.argv:
        raise SystemExit("Missing '--' separator; run via render-hero-icon.sh")
    argv = sys.argv[sys.argv.index("--") + 1:]
    if len(argv) < 2:
        raise SystemExit("usage: -- <weapon_name> <fbx_path> [preset]")
    preset = argv[2] if len(argv) >= 3 else "sword"
    return argv[0], argv[1], preset


# Camera presets, tuned per weapon silhouette shape.
#
#   sword — long, thin blades rendered diagonally, top-down-ish view with
#           a -45° camera roll so the blade runs bottom-left to top-right.
#   gun   — firearms with a 3/4 side-profile so barrel/body/grip all read,
#           mirrored so the muzzle lands on the right, then the same -45°
#           roll as the sword — grip at bottom-left, muzzle at top-right.
CAMERA_PRESETS = {
    "sword": {
        "direction": (0.0, 0.3, 1.0),
        "roll_deg": -45.0,
        "padding": 1.05,
    },
    "gun": {
        "direction": (-0.2, -1.0, 0.2),
        "roll_deg": 150.0,
        # Many gun meshes export with the pistol-grip pointing in the wrong
        # world direction for this camera angle. A 180° rotation around the
        # rifle's long axis flips the grip/optic rail to the correct side
        # without disturbing the barrel-to-stock silhouette.
        "flip_long_axis": True,
        # Looser framing so the grip + optic rail don't clip against the
        # edges — barrel length no longer has to fill the full frame.
        "padding": 1.05,
    },
}


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.outliner.orphans_purge(do_recursive=True)


def add_light(location, rotation_deg, energy: float, name: str):
    bpy.ops.object.light_add(type="SUN", location=location)
    light = bpy.context.object
    light.name = name
    light.rotation_euler = tuple(math.radians(a) for a in rotation_deg)
    light.data.energy = energy
    return light


def setup_hero_lighting() -> None:
    # Stronger key / softer fill / bright rim so the silhouette pops
    add_light((5, -5, 6), (45, 0, 45), energy=7.0, name="KeyLight")
    add_light((-5, -3, 4), (35, 0, -45), energy=2.0, name="FillLight")
    add_light((0, 5, 4), (-35, 0, 0), energy=5.0, name="RimLight")


def setup_render() -> None:
    scene = bpy.context.scene
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.resolution_x = RESOLUTION
    scene.render.resolution_y = RESOLUTION
    scene.render.resolution_percentage = 100
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"


def import_and_center(fbx_path: str, flip_long_axis: bool = False) -> float:
    bpy.ops.import_scene.fbx(filepath=fbx_path)
    mesh_objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not mesh_objs:
        raise RuntimeError(f"No meshes imported from {fbx_path}")

    # Promote meshes to scene root so location shifts work in world space
    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objs[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")

    min_co = mathutils.Vector((float("inf"),) * 3)
    max_co = mathutils.Vector((float("-inf"),) * 3)
    for obj in mesh_objs:
        for corner in obj.bound_box:
            world = obj.matrix_world @ mathutils.Vector(corner)
            for i in range(3):
                if world[i] < min_co[i]:
                    min_co[i] = world[i]
                if world[i] > max_co[i]:
                    max_co[i] = world[i]

    center = (min_co + max_co) * 0.5
    size = max_co - min_co
    for obj in mesh_objs:
        obj.matrix_world.translation -= center

    if flip_long_axis:
        long_axis = max(range(3), key=lambda i: size[i])
        axis_vec = mathutils.Vector((0.0, 0.0, 0.0))
        axis_vec[long_axis] = 1.0
        rot = mathutils.Matrix.Rotation(math.pi, 4, axis_vec)
        for obj in mesh_objs:
            obj.matrix_world = rot @ obj.matrix_world

    return max(size.x, size.y, size.z)


def configure_hero_camera(max_dim: float, preset: str):
    cfg = CAMERA_PRESETS.get(preset)
    if not cfg:
        raise SystemExit(f"unknown preset '{preset}'; choices: {list(CAMERA_PRESETS)}")
    direction = mathutils.Vector(cfg["direction"])
    camera_roll_deg = cfg["roll_deg"]
    name = "HeroCamera"
    if name in bpy.data.objects:
        camera = bpy.data.objects[name]
    else:
        cam_data = bpy.data.cameras.new(name)
        camera = bpy.data.objects.new(name, cam_data)
        bpy.context.scene.collection.objects.link(camera)

    camera.data.type = "ORTHO"
    camera.data.ortho_scale = max_dim * cfg.get("padding", FRAMING_PADDING)

    distance = max_dim * 3.0 + 2.0
    camera.location = direction.normalized() * distance

    # Look-at (camera faces -Z) + apply roll in the camera's local Z so
    # the subject's horizontal axis rotates into the frame's diagonal.
    base_rot = (-camera.location).to_track_quat("-Z", "Y")
    roll = mathutils.Quaternion(mathutils.Vector((0, 0, 1)), math.radians(camera_roll_deg))
    camera.rotation_euler = (base_rot @ roll).to_euler()

    bpy.context.scene.camera = camera


def main() -> None:
    weapon_name, fbx_path, preset = parse_args()
    if not os.path.isfile(fbx_path):
        raise SystemExit(f"FBX not found: {fbx_path}")

    cfg = CAMERA_PRESETS.get(preset)
    if not cfg:
        raise SystemExit(f"unknown preset '{preset}'; choices: {list(CAMERA_PRESETS)}")

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    output = os.path.join(OUTPUT_DIR, f"{weapon_name}_3d.png")

    clear_scene()
    setup_render()
    setup_hero_lighting()
    max_dim = import_and_center(fbx_path, flip_long_axis=cfg.get("flip_long_axis", False))
    configure_hero_camera(max_dim, preset)

    bpy.context.scene.render.filepath = output
    bpy.ops.render.render(write_still=True)
    print(f"[render_hero] wrote {output}")


if __name__ == "__main__":
    main()
