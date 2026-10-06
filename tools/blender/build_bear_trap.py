import math
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import bpy
from mathutils import Vector

from meshkit import export_glb, frustum, make_object, merged, reset_scene, rounded_box, torus, tube, vertex_color_material

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_PATH = os.path.abspath(ARGS[0]) if ARGS else os.path.join(os.getcwd(), "bear_trap.glb")

IRON = (0.32, 0.33, 0.37)
IRON_LIGHT = (0.62, 0.64, 0.68)
RUST = (0.62, 0.32, 0.15)
RADIUS = 0.55


def jaw(side):
    arc = [Vector((RADIUS * math.cos(a), side * RADIUS * math.sin(a), 0.04)) for a in (math.pi * i / 12 for i in range(13))]
    parts = [tube(arc, 0.045, sides=8, caps=True)]
    for i in range(1, 12):
        a = math.pi * i / 12
        base = Vector((RADIUS * math.cos(a), side * RADIUS * math.sin(a), 0.04))
        tip = base * 0.72 + Vector((0, 0, 0.14))
        parts.append(frustum(base, tip, 0.05, 0.0, segments=4))
    return merged(*parts)


def build():
    reset_scene()
    material = vertex_color_material("TrapVertexColor")
    base = merged(
        torus(RADIUS, 0.04, 28, 6, center=(0, 0, 0.04)),
        torus(RADIUS * 0.45, 0.03, 20, 6, center=(0, 0, 0.04)),
        rounded_box((RADIUS + 0.12, 0, 0.06), (0.22, 0.16, 0.1), 0.03, 2),
        rounded_box((-RADIUS - 0.12, 0, 0.06), (0.22, 0.16, 0.1), 0.03, 2),
    )
    objects = [
        make_object("TrapBase", base, IRON, sharp_angle=50),
        make_object("TrapPlate", frustum((0, 0, 0.02), (0, 0, 0.07), 0.2, 0.18, 16), RUST, sharp_angle=50),
        make_object("JawFar", jaw(1), IRON_LIGHT, sharp_angle=50),
        make_object("JawNear", jaw(-1), IRON_LIGHT, sharp_angle=50),
    ]
    for obj in objects:
        obj.data.materials.append(material)
    export_glb(OUT_PATH, objects, animations=False)
    print("TRAP tris", sum(len(p.vertices) - 2 for o in objects for p in o.data.polygons))


build()
