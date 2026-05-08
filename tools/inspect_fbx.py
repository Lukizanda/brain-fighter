"""
inspect_fbx.py — invoked by Blender in --background mode.

Imports one or more FBX files, reports each one's world-space bounding box,
and renders 3 orthographic views (looking down +X, +Y, +Z toward the bbox
center) so an outside reader (Claude) can see the imported orientation
without opening Blender. Used as the pre-step before tools/prep-fbx.sh:
the renders + bbox tell us which Euler rotation will land the mesh in
Roblox-correct orientation.

Args (positional, after `--` separator):
    output_dir  input1.fbx [input2.fbx ...]

Each input gets a sub-folder under output_dir named after the FBX basename,
containing bbox.json + view_pX.png / view_pY.png / view_pZ.png.

Render conventions:
    +X view: camera at +X looking toward origin (sees the Y/Z face)
    +Y view: camera at +Y looking toward origin (sees the X/Z face, "top")
    +Z view: camera at +Z looking toward origin (sees the X/Y face, "front")

Coordinates are Blender-frame post-import. Rotation Eulers passed to
fbx_reorient.py apply in this same frame.
"""

import sys
import os
import json
import math
import bpy
import numpy as np
from mathutils import Matrix as MMatrix


def parse_args() -> dict:
    if "--" not in sys.argv:
        raise SystemExit("Missing '--' separator; run via inspect-fbx wrapper.")
    argv = sys.argv[sys.argv.index("--") + 1:]
    if len(argv) < 2:
        raise SystemExit("Usage: inspect_fbx.py -- output_dir input1.fbx [input2.fbx ...]")
    return {"output_dir": argv[0], "inputs": argv[1:]}


def clear_scene() -> None:
    for obj in list(bpy.context.scene.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images,
                 bpy.data.cameras, bpy.data.lights):
        for d in list(coll):
            try:
                coll.remove(d)
            except RuntimeError:
                pass


def world_bbox(meshes):
    minv = [float("inf")] * 3
    maxv = [float("-inf")] * 3
    pts = []
    for o in meshes:
        m = o.matrix_world
        for v in o.data.vertices:
            wv = m @ v.co
            pts.append((wv.x, wv.y, wv.z))
            for i in range(3):
                if wv[i] < minv[i]:
                    minv[i] = wv[i]
                if wv[i] > maxv[i]:
                    maxv[i] = wv[i]
    size = [maxv[i] - minv[i] for i in range(3)]
    center = [(maxv[i] + minv[i]) / 2 for i in range(3)]
    return minv, maxv, size, center, pts


def principal_axes_and_euler(pts):
    """Run PCA, return (eigenvalues_desc, principal_axes_columns, suggested_euler_xyz_deg).

    Suggested Euler aligns:
      longest principal axis → +Y (blade direction in Blender frame post-import)
      medium                → +X
      shortest              → +Z
    Tip/butt sign is ambiguous from PCA alone; verify visually after applying.
    """
    arr = np.array(pts, dtype=np.float64)
    if len(arr) < 3:
        return None, None, None
    arr -= arr.mean(0)
    cov = (arr.T @ arr) / len(arr)
    evals, evecs = np.linalg.eigh(cov)  # ascending eigenvalues, columns = eigenvectors
    order = np.argsort(evals)[::-1]
    evals = evals[order]
    evecs = evecs[:, order]  # columns: longest, medium, shortest

    # We need rotation R such that R @ evecs = target_frame
    # target_frame columns: longest=Y, medium=X, shortest=Z
    target = np.array([
        [0.0, 1.0, 0.0],  # +Y
        [1.0, 0.0, 0.0],  # +X
        [0.0, 0.0, 1.0],  # +Z
    ]).T  # shape (3,3), columns = target axes
    R = target @ evecs.T

    # Force proper rotation (det = +1) — PCA eigenvectors are sign-ambiguous
    if np.linalg.det(R) < 0:
        evecs[:, 2] *= -1
        R = target @ evecs.T

    mat = MMatrix([list(row) for row in R])
    eul = mat.to_euler("XYZ")
    euler_deg = [math.degrees(eul.x), math.degrees(eul.y), math.degrees(eul.z)]
    return evals.tolist(), evecs.tolist(), euler_deg


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.film_transparent = False
    try:
        scene.eevee.taa_render_samples = 16
    except (AttributeError, TypeError):
        pass

    # Mid-gray background for contrast
    if "InspectWorld" not in bpy.data.worlds:
        world = bpy.data.worlds.new("InspectWorld")
    else:
        world = bpy.data.worlds["InspectWorld"]
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.18, 0.18, 0.22, 1.0)
        bg.inputs[1].default_value = 1.0
    scene.world = world


def add_lighting():
    bpy.ops.object.light_add(type="SUN", location=(5, 5, 5))
    bpy.context.object.data.energy = 4.0
    bpy.ops.object.light_add(type="SUN", location=(-5, -5, 5))
    bpy.context.object.data.energy = 2.0


def add_camera_and_target(center):
    bpy.ops.object.empty_add(location=center)
    target = bpy.context.object
    target.name = "InspectTarget"

    cam_data = bpy.data.cameras.new("InspectCam")
    cam = bpy.data.objects.new("InspectCam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.data.type = "ORTHO"

    con = cam.constraints.new("TRACK_TO")
    con.target = target
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    bpy.context.scene.camera = cam
    return cam, target


def render_view(cam, axis_index, sign, center, max_size, out_path):
    dist = max_size * 2.0 + 1.0
    pos = list(center)
    pos[axis_index] += sign * dist
    cam.location = pos
    cam.data.ortho_scale = max(max_size * 1.4, 1e-4)
    bpy.context.scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)


def process(input_fbx: str, output_root: str) -> dict:
    base = os.path.splitext(os.path.basename(input_fbx))[0]
    out_dir = os.path.join(output_root, base)
    os.makedirs(out_dir, exist_ok=True)

    clear_scene()
    bpy.ops.import_scene.fbx(filepath=input_fbx)

    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit(f"[inspect] no meshes in {input_fbx}")

    minv, maxv, size, center, pts = world_bbox(meshes)
    longest_axis = size.index(max(size))
    evals, evecs, suggested_euler = principal_axes_and_euler(pts)
    info = {
        "input": input_fbx,
        "mesh_count": len(meshes),
        "bbox_min": minv,
        "bbox_max": maxv,
        "size": size,
        "center": center,
        "longest_axis_aabb": ["X", "Y", "Z"][longest_axis],
        "longest_size_aabb": size[longest_axis],
        "pca_eigenvalues_desc": evals,
        "pca_axes_columns": evecs,
        "suggested_euler_xyz_deg": suggested_euler,
        "suggested_euler_note": "Aligns largest PCA axis to +Y, medium to +X, shortest to +Z. Tip/butt sign is ambiguous from PCA — verify visually and add 180° around Y if reversed.",
    }
    with open(os.path.join(out_dir, "bbox.json"), "w") as f:
        json.dump(info, f, indent=2)
    print(f"[inspect] {input_fbx}: size={size} longest_aabb={info['longest_axis_aabb']} suggested_euler={suggested_euler}")

    setup_render()
    add_lighting()
    cam, _ = add_camera_and_target(center)
    max_dim = max(size)

    views = [
        ("view_pX.png", 0, +1),
        ("view_pY.png", 1, +1),
        ("view_pZ.png", 2, +1),
    ]
    for filename, axis, sign in views:
        render_view(cam, axis, sign, center, max_dim, os.path.join(out_dir, filename))

    return info


def main():
    args = parse_args()
    os.makedirs(args["output_dir"], exist_ok=True)
    summary = []
    for fbx in args["inputs"]:
        summary.append(process(fbx, args["output_dir"]))
    with open(os.path.join(args["output_dir"], "_summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
    print(f"[inspect] wrote {len(summary)} reports under {args['output_dir']}")


if __name__ == "__main__":
    main()
