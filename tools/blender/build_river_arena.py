import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import bmesh
import bpy

from river_arena_shape import HALF_X, HALF_Z, color, height

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_PATH = os.path.abspath(ARGS[0]) if ARGS else os.path.join(os.getcwd(), "terrain.glb")


def axis_samples(half, dense_half, dense_step, sparse_step):
    values = []
    v = -half
    while v < half - 1e-6:
        values.append(round(v, 4))
        v += dense_step if abs(v) < dense_half else sparse_step
    values.append(half)
    return values


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    xs = axis_samples(HALF_X, 6.0, 0.25, 1.0)
    zs = axis_samples(HALF_Z, HALF_Z + 1, 0.5, 0.5)

    bm = bmesh.new()
    grid = [[bm.verts.new((x, -z, height(x, z))) for x in xs] for z in zs]
    for r in range(len(zs) - 1):
        for c in range(len(xs) - 1):
            face = bm.faces.new((grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]))
            face.smooth = True
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("Terrain")
    bm.to_mesh(mesh)
    bm.free()
    attr = mesh.color_attributes.new("Col", "BYTE_COLOR", "POINT")
    for i, v in enumerate(mesh.vertices):
        x, z = v.co.x, -v.co.y
        attr.data[i].color_srgb = (*color(x, z, v.co.z), 1.0)
    mesh.color_attributes.active_color = attr

    obj = bpy.data.objects.new("Terrain", mesh)
    bpy.context.collection.objects.link(obj)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    print(f"TERRAIN tris={sum(len(p.vertices) - 2 for p in mesh.polygons)}")

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT_PATH,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=False,
        export_vertex_color="ACTIVE",
    )


if __name__ == "__main__":
    build()
