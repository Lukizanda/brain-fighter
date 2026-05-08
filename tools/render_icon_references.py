"""
render_icon_references.py — invoked by Blender in --background mode.

For each weapon listed in WEAPONS, imports the FBX, centers the mesh,
and renders 4 reference PNGs (front, 3/4 iso, side, top) with a
transparent background. These are meant to feed into Gemini (or any
image-to-icon pipeline) as multi-angle visual references for generating
the final HUD icons.

Output layout:
    <OUTPUT_ROOT>/<WeaponName>/Front.png
    <OUTPUT_ROOT>/<WeaponName>/ThreeQuarter.png
    <OUTPUT_ROOT>/<WeaponName>/Side.png
    <OUTPUT_ROOT>/<WeaponName>/Top.png

Each angle uses an orthographic camera sized to the weapon's bounding
box (consistent framing across different-sized weapons), with a simple
three-point lighting rig so the silhouette reads clearly.

To add more weapons: append to the WEAPONS list below. No other code
changes needed.

Run via tools/render-icons.sh.
"""

from __future__ import annotations

import math
import os
from typing import Tuple

import bpy
import mathutils


# ----------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------

OUTPUT_ROOT = r"C:\Google Drive\Work\AI\icon_references"

RESOLUTION = 1024  # square; matches typical icon reference upload size

# Margin multiplier for orthographic framing (1.0 = tight to bbox, higher = more padding)
FRAMING_PADDING = 1.25

WEAPONS = [
    {
        "name": "LaserPistol",
        "fbx": r"C:\Google Drive\Work\AI\Meshes\Meshy_AI_A_sci_fi_energy_blast_0416032141_texture_fbx\Meshy_AI_A_sci_fi_energy_blast_0416032141_texture_fbx\Meshy_AI_A_sci_fi_energy_blast_0416032141_texture.fbx",
    },
    {
        "name": "Sword",
        "fbx": r"C:\Google Drive\Work\AI\Meshes\Meshy_AI_Medieval_long_sword_f_0415032247_texture_fbx\Meshy_AI_Medieval_long_sword_f_0415032247_texture_fbx\Meshy_AI_Medieval_long_sword_f_0415032247_texture.fbx",
    },
]

# Camera positions are unit vectors (we scale by the bounding-box distance
# per weapon). Blender is Z-up, -Y-forward. Camera looks at world origin.
ANGLES = [
    {"name": "Front",         "dir": mathutils.Vector(( 0.0, -1.0,  0.0))},
    {"name": "ThreeQuarter",  "dir": mathutils.Vector(( 0.8, -0.8,  0.5))},
    {"name": "Side",          "dir": mathutils.Vector(( 1.0,  0.0,  0.0))},
    {"name": "Top",           "dir": mathutils.Vector(( 0.0,  0.0,  1.0))},
]


# ----------------------------------------------------------------------
# Scene / lighting setup (once per weapon)
# ----------------------------------------------------------------------

def clear_scene() -> None:
    """Wipe all objects from the current scene."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    # Also purge orphan datablocks so textures from the previous import don't linger
    bpy.ops.outliner.orphans_purge(do_recursive=True)


def add_light(location, rotation_deg, energy: float, name: str):
    bpy.ops.object.light_add(type="SUN", location=location)
    light = bpy.context.object
    light.name = name
    light.rotation_euler = tuple(math.radians(a) for a in rotation_deg)
    light.data.energy = energy
    return light


def setup_three_point_lighting() -> None:
    """Key (bright front-right), fill (softer front-left), rim (from behind)."""
    add_light((5, -5, 6), (45, 0, 45), energy=5.0, name="KeyLight")
    add_light((-5, -3, 4), (35, 0, -45), energy=2.5, name="FillLight")
    add_light((0, 5, 4), (-35, 0, 0), energy=3.5, name="RimLight")


def setup_render() -> None:
    scene = bpy.context.scene

    # Transparent PNG output (alpha channel, no green screen — Gemini handles RGBA fine
    # and we avoid any chroma-fringe artifacts)
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"

    scene.render.resolution_x = RESOLUTION
    scene.render.resolution_y = RESOLUTION
    scene.render.resolution_percentage = 100

    # Eevee is fast and fine for reference material; Cycles would give nicer
    # materials but takes far longer per weapon.
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"


# ----------------------------------------------------------------------
# Mesh import + normalization
# ----------------------------------------------------------------------

def import_and_center(fbx_path: str) -> Tuple[mathutils.Vector, float]:
    """
    Imports the FBX, recenters all mesh objects so the combined bounding
    box is centered at the world origin, and returns (bbox_min, max_dim)
    useful for sizing the orthographic camera.
    """
    bpy.ops.import_scene.fbx(filepath=fbx_path)

    mesh_objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not mesh_objs:
        raise RuntimeError(f"No meshes imported from {fbx_path}")

    # Meshy FBX files often parent meshes under an Empty (the "Armature" or
    # "Root" node). Clearing parents (keeping transform) promotes each mesh
    # to scene root so `obj.location` becomes world-space — needed for the
    # centering math below to actually shift in world space.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objs[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")

    # Compute world-space bounding box across all meshes
    min_co = mathutils.Vector((float("inf"),) * 3)
    max_co = mathutils.Vector((float("-inf"),) * 3)
    for obj in mesh_objs:
        for corner in obj.bound_box:
            world_corner = obj.matrix_world @ mathutils.Vector(corner)
            for i in range(3):
                if world_corner[i] < min_co[i]:
                    min_co[i] = world_corner[i]
                if world_corner[i] > max_co[i]:
                    max_co[i] = world_corner[i]

    center = (min_co + max_co) * 0.5
    size = max_co - min_co
    max_dim = max(size.x, size.y, size.z)

    # Shift each mesh so the collective bbox center sits at the world origin.
    # Uses matrix_world.translation so the shift is world-space regardless
    # of any remaining parent/transform quirks.
    for obj in mesh_objs:
        obj.matrix_world.translation -= center

    return max_co - center, max_dim


# ----------------------------------------------------------------------
# Per-angle camera placement + render
# ----------------------------------------------------------------------

def configure_ortho_camera(direction: mathutils.Vector, max_dim: float, distance_scale: float = 3.0):
    """Create (or reuse) a camera, place it along `direction` pointing at origin,
    using orthographic projection sized to the bounding box."""
    cam_name = "IconCamera"
    if cam_name in bpy.data.objects:
        camera = bpy.data.objects[cam_name]
    else:
        cam_data = bpy.data.cameras.new(cam_name)
        camera = bpy.data.objects.new(cam_name, cam_data)
        bpy.context.scene.collection.objects.link(camera)

    camera.data.type = "ORTHO"
    # Pad the ortho scale so silhouettes have breathing room in the frame
    camera.data.ortho_scale = max_dim * FRAMING_PADDING * 1.4

    # Place camera along direction unit vector; distance doesn't affect ortho framing
    # but must clear the bounding box so nothing clips.
    pos = direction.normalized() * (max_dim * distance_scale + 2.0)
    camera.location = pos

    # Point camera at origin. Blender cameras face -Z in local space; rotate so -Z
    # aligns with the vector from camera to origin.
    to_origin = -pos
    rot = to_origin.to_track_quat("-Z", "Y")
    camera.rotation_euler = rot.to_euler()

    bpy.context.scene.camera = camera
    return camera


def render_to(output_path: str) -> None:
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    bpy.context.scene.render.filepath = output_path
    bpy.ops.render.render(write_still=True)


# ----------------------------------------------------------------------
# Main loop
# ----------------------------------------------------------------------

def main() -> None:
    print(f"[render_icons] rendering {len(WEAPONS)} weapon(s) × {len(ANGLES)} angles "
          f"→ {OUTPUT_ROOT}")

    for weapon in WEAPONS:
        name = weapon["name"]
        fbx = weapon["fbx"]

        print(f"[render_icons] === {name} ===")
        if not os.path.isfile(fbx):
            print(f"  ! fbx not found, skipping: {fbx}")
            continue

        clear_scene()
        setup_render()
        setup_three_point_lighting()

        _bbox_corner, max_dim = import_and_center(fbx)
        print(f"  bbox max dimension = {max_dim:.3f}")

        for angle in ANGLES:
            configure_ortho_camera(angle["dir"], max_dim)
            out_path = os.path.join(OUTPUT_ROOT, name, f"{angle['name']}.png")
            render_to(out_path)
            print(f"  wrote {out_path}")

    print("[render_icons] done")


if __name__ == "__main__":
    main()
