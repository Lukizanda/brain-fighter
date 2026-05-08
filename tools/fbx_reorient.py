"""
fbx_reorient.py — invoked by Blender in --background mode.

Re-orients a Meshy FBX to Roblox axis/scale conventions while KEEPING
texture bindings intact. Output is safe for both Studio's Import 3D and
Open Cloud Model upload.

Imports an FBX, applies a rotation (and optional uniform scale), strips
any skin deformer / armature bindings that Meshy sometimes leaves in a
broken state, bakes the transform into the mesh data, and re-exports an
FBX with Roblox's expected axis convention (+Y up, -Z forward), with
textures embedded so Studio doesn't hit "skin paths can't be read".

Args (positional, after the `--` separator Blender requires):
    input_fbx  output_fbx  [rx_deg ry_deg rz_deg]  [--scale FACTOR]

Defaults (tuned for Meshy FBX output):
    rotation = (0, 0, 90)   # composition of Blender's axis flip and Studio fixups
    scale    = 0.015          # Meshy meshes ~100x oversized; 0.015 lands weapons ~3-4 studs
"""

import sys
import math
import bpy


def parse_args() -> dict:
    # Blender passes everything after "--" to the script; args before that are Blender's own.
    if "--" not in sys.argv:
        raise SystemExit("Missing '--' separator; run via prep-fbx wrapper.")
    argv = sys.argv[sys.argv.index("--") + 1:]

    if len(argv) < 2:
        raise SystemExit("Usage: fbx_reorient.py -- input.fbx output.fbx [rx ry rz] [--scale F]")

    result = {
        "input": argv[0],
        "output": argv[1],
        "rotation_deg": (0.0, 0.0, 90.0),
        "scale": 0.015,
    }

    # Optional Euler triple
    tail = argv[2:]
    if len(tail) >= 3 and not tail[0].startswith("--"):
        try:
            result["rotation_deg"] = (float(tail[0]), float(tail[1]), float(tail[2]))
            tail = tail[3:]
        except ValueError:
            pass

    # Optional --scale flag
    if "--scale" in tail:
        i = tail.index("--scale")
        result["scale"] = float(tail[i + 1])

    return result


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def main() -> None:
    args = parse_args()
    print(f"[fbx_reorient] input={args['input']} output={args['output']} "
          f"rotation={args['rotation_deg']} scale={args['scale']}")

    clear_scene()
    bpy.ops.import_scene.fbx(filepath=args["input"])

    # Collect imported mesh objects
    mesh_objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not mesh_objs:
        raise SystemExit("[fbx_reorient] no meshes in imported FBX")

    rx, ry, rz = args["rotation_deg"]
    scale = args["scale"]

    # Strip skin/armature bindings. Meshy FBX sometimes ships with a skin
    # deformer pointing at an armature that was never populated. When we
    # later export mesh-only (or simply re-serialize), Studio sees a dangling
    # skin-weight path and refuses the file with "skin paths can't be read".
    # Removing Armature modifiers + any armature objects entirely makes the
    # exported FBX a clean static mesh.
    for obj in mesh_objs:
        for mod in list(obj.modifiers):
            if mod.type == "ARMATURE":
                obj.modifiers.remove(mod)
        if obj.vertex_groups:
            for vg in list(obj.vertex_groups):
                obj.vertex_groups.remove(vg)
    for obj in list(bpy.context.scene.objects):
        if obj.type == "ARMATURE":
            bpy.data.objects.remove(obj, do_unlink=True)

    # Apply rotation + scale to each mesh, then bake into mesh data so the
    # exported FBX has identity transforms and Roblox imports the "corrected"
    # geometry directly.
    for obj in mesh_objs:
        obj.rotation_euler = (math.radians(rx), math.radians(ry), math.radians(rz))
        obj.scale = (scale, scale, scale)

    # Select and bake
    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objs[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    # Roblox convention: +Y up, -Z forward. Blender exports with these defaults.
    # path_mode=COPY + embed_textures=True bundles the texture PNGs directly
    # into the FBX binary so Studio's Import 3D can find them without needing
    # the sibling _metallic / _normal / _roughness files on disk.
    bpy.ops.export_scene.fbx(
        filepath=args["output"],
        use_selection=True,
        axis_forward="-Z",
        axis_up="Y",
        object_types={"MESH"},
        bake_space_transform=True,
        path_mode="COPY",
        embed_textures=True,
    )
    print(f"[fbx_reorient] wrote {args['output']}")


if __name__ == "__main__":
    main()
