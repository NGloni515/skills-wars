import math
import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

from gaff_animations import build_animations
from meshkit import (
    blend_along, bind, build_rig, bvh, ellipsoid, export_glb, frustum, join, lathe, make_object, merged,
    polyline, remeshed, reset_scene, rounded_box, smoothstep, torus, transform, triangles, tube,
    vertex_color_material,
)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = os.path.abspath(ARGS[0]) if ARGS else os.getcwd()
PREVIEW_DIR = os.path.abspath(ARGS[1]) if len(ARGS) > 1 else None

PROJECTILE_HOOK_SCALE = 1.3
HAND_HOOK = Matrix(((0, 0, -1), (-1, 0, 0), (0, 1, 0)))

SKIN = (0.92, 0.6, 0.44)
NOSE = (0.9, 0.46, 0.38)
BEARD = (0.6, 0.29, 0.12)
MUSTACHE = (0.7, 0.36, 0.16)
SWEATER = (0.86, 0.62, 0.2)
SWEATER_DARK = (0.7, 0.45, 0.13)
TROUSERS = (0.33, 0.27, 0.24)
TROUSERS_DARK = (0.25, 0.2, 0.18)
BOOTS = (0.36, 0.22, 0.14)
SOLE = (0.14, 0.11, 0.1)
LEATHER = (0.5, 0.3, 0.15)
IRON = (0.46, 0.5, 0.56)
IRON_DARK = (0.3, 0.32, 0.37)
PAINT = (0.95, 0.52, 0.12)
STEEL = (0.84, 0.88, 0.93)
EYE_WHITE = (0.98, 0.98, 0.96)
PUPIL = (0.06, 0.05, 0.08)
FISH = (0.38, 0.66, 0.78)
FISH_FIN = (0.95, 0.62, 0.25)
# The hero shader tints any pure-magenta hue with the team color, keeping its brightness.
TEAM = (1.0, 0.0, 1.0)
TEAM_DARK = (0.72, 0.0, 0.72)

BONES = [
    ("root", (0, 0, 0), (0, 0, 0.25), None),
    ("hips", (0, 0, 0.78), (0, 0, 0.95), "root"),
    ("spine", (0, 0, 0.95), (0, 0, 1.25), "hips"),
    ("chest", (0, 0, 1.25), (0, 0, 1.55), "spine"),
    ("head", (0, -0.08, 1.55), (0, -0.08, 2.0), "chest"),
    ("upper_arm.L", (0.6, 0, 1.42), (0.78, -0.02, 1.08), "chest"),
    ("forearm.L", (0.78, -0.02, 1.08), (0.84, -0.1, 0.8), "upper_arm.L"),
    ("hand.L", (0.84, -0.1, 0.8), (0.86, -0.14, 0.6), "forearm.L"),
    ("upper_arm.R", (-0.64, 0, 1.42), (-0.86, -0.02, 1.06), "chest"),
    ("forearm.R", (-0.86, -0.02, 1.06), (-0.93, -0.14, 0.76), "upper_arm.R"),
    ("hand.R", (-0.93, -0.14, 0.76), (-0.95, -0.2, 0.52), "forearm.R"),
    ("hook_socket", (-0.95, -0.2, 0.66), (-0.95, -0.2, 0.42), "hand.R"),
    ("chain_socket", (-1.23, -0.08, 0.92), (-1.23, -0.28, 0.92), "forearm.R"),
    ("thigh.L", (0.24, 0, 0.78), (0.25, -0.02, 0.44), "hips"),
    ("shin.L", (0.25, -0.02, 0.44), (0.26, 0, 0.16), "thigh.L"),
    ("foot.L", (0.26, 0, 0.16), (0.26, -0.24, 0.06), "shin.L"),
    ("thigh.R", (-0.24, 0, 0.78), (-0.25, -0.02, 0.44), "hips"),
    ("shin.R", (-0.25, -0.02, 0.44), (-0.26, 0, 0.16), "thigh.R"),
    ("foot.R", (-0.26, 0, 0.16), (-0.26, -0.24, 0.06), "shin.R"),
]

HEAD_CENTER = Vector((0, -0.1, 1.8))
HEAD_SIZE = Vector((0.33, 0.31, 0.32))


def head_front_y(x, z):
    inside = 1.0 - (x / HEAD_SIZE.x) ** 2 - ((z - HEAD_CENTER.z) / HEAD_SIZE.z) ** 2
    return HEAD_CENTER.y - HEAD_SIZE.y * math.sqrt(max(0.0, inside))


def lerp_list(values, steps):
    out = []
    for a, b in zip(values, values[1:]):
        out.extend(a + (b - a) * i / steps for i in range(steps))
    out.append(values[-1])
    return out


def torso_weights(co):
    hips = 1.0 - smoothstep(0.9, 1.05, co.z)
    chest = smoothstep(1.2, 1.38, co.z)
    return {"hips": hips, "spine": max(0.0, 1.0 - hips - chest), "chest": chest}


def build_torso():
    bm = remeshed([
        ellipsoid((0, -0.06, 1.05), (0.6, 0.52, 0.48)),
        ellipsoid((0, 0, 1.36), (0.66, 0.44, 0.3)),
        ellipsoid((0, 0, 0.8), (0.44, 0.36, 0.24)),
        ellipsoid((0, 0.02, 1.52), (0.32, 0.28, 0.14)),
    ], voxel_size=0.03, target_tris=1300)
    return bm, bvh(bm)


def surface_front_y(tree, x, z, fallback=0.0):
    hit, _, _, _ = tree.ray_cast(Vector((x, -2.0, z)), Vector((0, 1, 0)))
    return hit.y if hit else fallback


def build_apron(tree):
    cols, rows = 11, 15
    grid = []
    previous = None
    for r in range(rows):
        t = r / (rows - 1)
        z = 1.36 + (0.6 - 1.36) * t
        half = 0.3 + 0.13 * t
        row = []
        for c in range(cols):
            x = -half + 2 * half * c / (cols - 1)
            y = surface_front_y(tree, x, z) - 0.022
            if previous is not None:
                y = min(y, previous[c].y)
            row.append(Vector((x, y, z)))
        previous = row
        grid.append(row)
    for r, row in enumerate(grid):
        flare = 0.05 * smoothstep(0.6, 1.0, r / (rows - 1))
        for v in row:
            v.y -= flare
    bm = bmesh.new()
    verts = [[bm.verts.new(v) for v in row] for row in grid]
    for r in range(rows - 1):
        for c in range(cols - 1):
            bm.faces.new((verts[r][c], verts[r + 1][c], verts[r + 1][c + 1], verts[r][c + 1]))
    bmesh.ops.solidify(bm, geom=list(bm.faces), thickness=0.016)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm, grid


def build_apron_strap(tree):
    path = [(-0.27, 1.34), (-0.22, 1.47), (-0.13, 1.57), (0.0, 1.62), (0.13, 1.57), (0.22, 1.47), (0.27, 1.34)]
    points = []
    for x, z in path:
        nearest, normal, _, _ = tree.find_nearest(Vector((x, -0.2, z)))
        points.append(nearest + normal * 0.03)
    smooth = polyline(points, 3)
    return tube(smooth, 0.024, sides=8)


def build_belt(tree):
    center = Vector((0, -0.02, 0.9))

    def radius_at(angle):
        direction = Vector((math.cos(angle), math.sin(angle), 0))
        hit, _, _, _ = tree.ray_cast(center + direction * 1.5, -direction)
        return (hit - center).length if hit else 0.4

    def profile(angle):
        r = radius_at(angle)
        return [(r - 0.01, 0.86), (r + 0.014, 0.86), (r + 0.014, 0.94), (r - 0.01, 0.94)]

    return transform(lathe(profile, segments=28), Matrix.Translation((0, -0.02, 0)))


def build_pocket_and_fish(apron_grid):
    pocket_z = 0.93
    row = min(apron_grid, key=lambda r: abs(r[0].z - pocket_z))
    front = min(row, key=lambda v: abs(v.x + 0.2)).y
    pocket = rounded_box((-0.2, front - 0.014, pocket_z), (0.2, 0.022, 0.17), 0.01, segments=2)
    fish_y = front + 0.01
    tilt = Euler((0, math.radians(14), 0))
    fish = ellipsoid((-0.21, fish_y, 1.03), (0.045, 0.032, 0.1), 12, 8, rotation=tilt)
    fins = merged(
        ellipsoid((-0.245, fish_y, 1.14), (0.035, 0.012, 0.055), 10, 6, rotation=Euler((0, math.radians(40), 0))),
        ellipsoid((-0.19, fish_y, 1.14), (0.035, 0.012, 0.055), 10, 6, rotation=Euler((0, math.radians(-25), 0))),
    )
    fish_eye = ellipsoid((-0.2, fish_y - 0.03, 0.97), (0.012, 0.008, 0.012), 8, 6)
    return pocket, fish, fins, fish_eye


def build_leg(side):
    x = 0.24 * side
    hip = Vector((x, 0, 0.78))
    knee = Vector((x + 0.01 * side, -0.02, 0.44))
    ankle = Vector((x + 0.02 * side, 0, 0.16))
    bone = ".L" if side > 0 else ".R"
    points = polyline([hip, knee, ankle], 5)
    radii = lerp_list([0.17, 0.15, 0.135], 5)
    weights = blend_along(hip, ankle, knee, "thigh" + bone, "shin" + bone, 0.05)
    boot_x = x + 0.02 * side
    return [
        (f"leg{bone}", tube(points, radii, sides=12), TROUSERS, weights),
        (f"hip_ball{bone}", ellipsoid(hip, (0.18, 0.18, 0.18), 10, 6), TROUSERS, "thigh" + bone),
        (f"cuff{bone}", torus(0.148, 0.035, 14, 5, center=ankle + Vector((0, 0, 0.1))), TROUSERS_DARK, "shin" + bone),
        (f"boot{bone}", rounded_box((boot_x, -0.08, 0.1), (0.3, 0.46, 0.2), 0.08), BOOTS, "foot" + bone),
        (f"shaft{bone}", frustum((boot_x, 0, 0.12), (boot_x, 0, 0.27), 0.16, 0.152, 18), BOOTS, "foot" + bone),
        (f"sole{bone}", rounded_box((boot_x, -0.08, 0.03), (0.32, 0.48, 0.06), 0.025, 2), SOLE, "foot" + bone),
    ]


def build_arm(side, big):
    s = side
    bone = ".L" if side > 0 else ".R"
    if big:
        shoulder, elbow, wrist = Vector((0.64 * s, 0, 1.42)), Vector((0.86 * s, -0.02, 1.06)), Vector((0.93 * s, -0.14, 0.76))
        sleeve_r, forearm_r = [0.21, 0.18, 0.195], [0.17, 0.2, 0.215, 0.2, 0.165]
        palm, palm_size = Vector((0.95 * s, -0.19, 0.6)), (0.19, 0.17, 0.18)
        thumb, thumb_size = Vector((0.86 * s, -0.3, 0.66)), (0.07, 0.06, 0.08)
    else:
        shoulder, elbow, wrist = Vector((0.6 * s, 0, 1.42)), Vector((0.78 * s, -0.02, 1.08)), Vector((0.84 * s, -0.1, 0.8))
        sleeve_r, forearm_r = [0.155, 0.13, 0.142], [0.12, 0.125, 0.12, 0.112]
        palm, palm_size = Vector((0.86 * s, -0.13, 0.7)), (0.13, 0.12, 0.13)
        thumb, thumb_size = Vector((0.8 * s, -0.2, 0.74)), (0.05, 0.045, 0.065)
    forearm_dir = (wrist - elbow).normalized()
    sleeve_end = elbow + forearm_dir * 0.09
    sleeve_points = polyline([shoulder, elbow], 6)[:-1] + polyline([elbow, sleeve_end], 2)
    sleeve_radii = lerp_list(sleeve_r[:2], 6)[:-1] + lerp_list(sleeve_r[1:], 2)
    weights = blend_along(shoulder, wrist, elbow, "upper_arm" + bone, "forearm" + bone, 0.05)
    forearm_points = polyline([elbow, wrist + forearm_dir * 0.03], 8)
    forearm_radii = lerp_list(forearm_r, 8 // (len(forearm_r) - 1))
    forearm_radii = (forearm_radii + [forearm_r[-1]] * len(forearm_points))[:len(forearm_points)]
    return [
        (f"shoulder{bone}", ellipsoid(shoulder, (sleeve_r[0] + 0.02,) * 3, 10, 6), SWEATER, "upper_arm" + bone),
        (f"sleeve{bone}", tube(sleeve_points, sleeve_radii, sides=12), SWEATER, weights),
        (f"sleeve_cuff{bone}", torus(sleeve_r[2] + 0.004, 0.032 if not big else 0.042, 14, 5, center=sleeve_end, axis=forearm_dir), SWEATER_DARK, "forearm" + bone),
        (f"forearm{bone}", tube(forearm_points, forearm_radii, sides=12), SKIN, "forearm" + bone),
        (f"palm{bone}", ellipsoid(palm, palm_size, 12, 8), SKIN, "hand" + bone),
        (f"thumb{bone}", ellipsoid(thumb, thumb_size, 8, 6), SKIN, "hand" + bone),
    ], (elbow, wrist, forearm_r)


def build_winch(elbow, wrist, forearm_r):
    axis = Vector((1, 0, 0))
    c = Vector((-1.23, -0.08, 0.92))
    parts = [
        ("winch_mount", rounded_box((-1.1, -0.08, 0.92), (0.12, 0.13, 0.13), 0.025, 2), IRON_DARK),
        ("winch_drum", frustum((-1.15, c.y, c.z), (-1.31, c.y, c.z), 0.12, 0.12, 14), IRON),
        ("winch_plate_in", frustum((-1.13, c.y, c.z), (-1.16, c.y, c.z), 0.2, 0.2, 16), PAINT),
        ("winch_plate_out", frustum((-1.3, c.y, c.z), (-1.33, c.y, c.z), 0.2, 0.2, 16), PAINT),
        ("winch_hub", ellipsoid((-1.345, c.y, c.z), (0.04, 0.04, 0.04), 10, 6), IRON_DARK),
        ("winch_crank", rounded_box((-1.36, c.y, 1.0), (0.03, 0.045, 0.19), 0.012, 2), PAINT),
        ("winch_knob", frustum((-1.36, c.y, 1.08), (-1.45, c.y, 1.08), 0.035, 0.035, 12), LEATHER),
    ]
    for i, x in enumerate((-1.2, -1.26)):
        parts.append((f"winch_chain_{i}", torus(0.125, 0.022, 14, 4, center=(x, c.y, c.z), axis=axis), IRON_DARK))
    direction = (wrist - elbow)
    for i, t in enumerate((0.3, 0.72)):
        center = elbow + direction * t
        radius = forearm_r[1] + 0.012 if t < 0.5 else forearm_r[3] + 0.012
        parts.append((f"strap_{i}", torus(radius, 0.024, 14, 4, center=center, axis=direction), LEATHER))
    return [(name, bm, color, "forearm.R") for name, bm, color in parts]


def build_head():
    eye_z = 1.88
    parts = [
        ("head", ellipsoid(HEAD_CENTER, HEAD_SIZE, 24, 12), SKIN),
        ("nose", ellipsoid((0, -0.44, 1.78), (0.1, 0.09, 0.085), 12, 8), NOSE),
    ]
    for s in (1, -1):
        sclera_y = head_front_y(0.12, eye_z) + 0.012
        parts += [
            (f"ear_{s}", ellipsoid((0.32 * s, -0.08, 1.79), (0.05, 0.08, 0.1), 12, 8), SKIN),
            (f"sclera_{s}", ellipsoid((0.12 * s, sclera_y, eye_z), (0.075, 0.045, 0.085), 10, 8), EYE_WHITE),
            (f"pupil_{s}", ellipsoid((0.115 * s, sclera_y - 0.04, eye_z - 0.01), (0.037, 0.02, 0.045), 8, 6), PUPIL),
            (f"glint_{s}", ellipsoid((0.1 * s, sclera_y - 0.058, eye_z + 0.01), (0.013, 0.008, 0.013), 8, 6), EYE_WHITE),
        ]
        brow = [(0.045 * s, 1.948), (0.13 * s, 1.972), (0.21 * s, 1.982)]
        brow_points = [Vector((x, head_front_y(x, z) - 0.018, z)) for x, z in brow]
        parts.append((f"brow_{s}", tube(polyline(brow_points, 3), lerp_list([0.03, 0.036, 0.024], 3), sides=10), BEARD))

    beard = remeshed([
        ellipsoid((0, -0.3, 1.6), (0.27, 0.2, 0.2)),
        ellipsoid((0, -0.2, 1.67), (0.3, 0.2, 0.14)),
        ellipsoid((0.21, -0.24, 1.7), (0.13, 0.13, 0.15)),
        ellipsoid((-0.21, -0.24, 1.7), (0.13, 0.13, 0.15)),
    ], voxel_size=0.025, target_tris=600)
    parts.append(("beard", beard, BEARD))

    mustache_path = [(-0.22, -0.43, 1.655), (-0.1, -0.5, 1.715), (0.0, -0.515, 1.725), (0.1, -0.5, 1.715), (0.22, -0.43, 1.655)]
    parts.append(("mustache", tube(polyline(mustache_path, 3), lerp_list([0.022, 0.042, 0.048, 0.042, 0.022], 3), sides=12), MUSTACHE))

    parts.append(("hat_crown", ellipsoid((0, -0.1, 2.08), (0.33, 0.33, 0.22), 20, 10), TEAM))
    parts.append(("hat_band", torus(0.333, 0.026, 20, 5, center=(0, -0.1, 2.125)), TEAM_DARK))
    parts.append(("hat_brim", build_brim(), TEAM))
    return [(name, bm, color, "head") for name, bm, color in parts]


def build_brim():
    inner, z0, thickness = 0.3, 2.09, 0.036

    def profile(angle):
        back = max(0.0, math.sin(angle))
        outer = 0.52 + 0.14 * back ** 1.5
        droop_max = 0.04 + 0.1 * back
        steps = [i / 3 for i in range(4)]

        def droop(f):
            return droop_max * f ** 1.6

        top = [(inner + f * (outer - inner), z0 + thickness / 2 - droop(f)) for f in steps]
        rim = [(outer + 0.016, z0 - droop(1.0))]
        bottom = [(inner + f * (outer - inner), z0 - thickness / 2 - droop(f)) for f in reversed(steps)]
        return top + rim + bottom

    return transform(lathe(profile, segments=24), Matrix.Translation((0, -0.1, 0)))


def hook_mesh(origin=(0, 0, 0), scale=1.0, orientation=Matrix.Identity(3)):
    arc_center = Vector((0.11, -0.32, 0))
    arc = [
        arc_center + 0.11 * Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0))
        for a in range(195, 361, 15)
    ]
    path = [Vector((0, 0, 0)), Vector((0, -0.16, 0)), Vector((0, -0.3, 0)), *arc, Vector((0.22, -0.26, 0))]
    shape = merged(
        tube(path, 0.035, sides=8),
        frustum((0.22, -0.26, 0), (0.22, -0.1, 0), 0.07, 0.0, segments=8),
        torus(0.045, 0.018, 10, 4, center=(0, 0.04, 0), axis=(1, 0, 0)),
    )
    return transform(shape, Matrix.Translation(origin) @ orientation.to_4x4() @ Matrix.Scale(scale, 4))


def build_body():
    torso_bm, tree = build_torso()
    apron_bm, apron_grid = build_apron(tree)
    pocket, fish, fins, fish_eye = build_pocket_and_fish(apron_grid)
    parts = [
        ("torso", torso_bm, SWEATER, torso_weights),
        ("apron", apron_bm, TEAM, torso_weights),
        ("apron_strap", build_apron_strap(tree), TEAM, "chest"),
        ("pocket", pocket, TEAM_DARK, "spine"),
        ("fish", fish, FISH, "spine"),
        ("fish_fins", fins, FISH_FIN, "spine"),
        ("fish_eye", fish_eye, PUPIL, "spine"),
        ("belt", build_belt(tree), LEATHER, "hips"),
        ("collar", torus(0.27, 0.07, 18, 6, center=(0, 0.02, 1.6)), SWEATER_DARK, "chest"),
    ]
    parts += build_leg(1) + build_leg(-1)
    left_arm, _ = build_arm(1, big=False)
    right_arm, (elbow, wrist, forearm_r) = build_arm(-1, big=True)
    parts += left_arm + right_arm
    parts += build_head()

    objects = [make_object(name, bm, color, weights) for name, bm, color, weights in parts]
    objects += [make_object(name, bm, color, weights, sharp_angle=40) for name, bm, color, weights in build_winch(elbow, wrist, forearm_r)]
    body = join(objects, "Gaff")
    hook = make_object("HookHead", hook_mesh((-0.95, -0.2, 0.68), orientation=HAND_HOOK), STEEL, "hook_socket", sharp_angle=60)
    return body, hook


def aim(cam, location, target):
    cam.location = location
    cam.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()


def render_previews(rig, hidden):
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    scene = bpy.context.scene
    for obj in hidden:
        obj.hide_render = True
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "VERTEX"
    shading.show_shadows = True
    shading.show_cavity = True
    shading.cavity_type = "WORLD"
    shading.show_object_outline = True
    scene.world = bpy.data.worlds.new("Preview")
    scene.world.color = (0.55, 0.62, 0.66)
    scene.render.image_settings.file_format = "PNG"

    ground = make_object("Ground", rounded_box((0, 0, -0.05), (8, 8, 0.1), 0.01, 1), (0.42, 0.6, 0.33))
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 50

    def shot(path, location, target, size, lens=50):
        cam.data.lens = lens
        scene.render.resolution_x, scene.render.resolution_y = size
        aim(cam, location, target)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)

    actions = {a.name: a for a in bpy.data.actions}

    def use(action_name, frame):
        rig.animation_data.action = actions[action_name]
        rig.animation_data.action_slot = actions[action_name].slots[0]
        scene.frame_set(frame)

    use("idle-loop", 0)
    views = {
        "front34": ((3.2, -4.8, 2.6), (0, 0, 1.05), 50),
        "back34": ((-3.2, 4.8, 2.6), (0, 0, 1.05), 50),
        "game_top": ((0, -4.2, 6.6), (0, 0, 0.9), 50),
        "face": ((0.9, -2.4, 2.0), (0, -0.2, 1.78), 85),
    }
    for name, (loc, target, lens) in views.items():
        shot(os.path.join(PREVIEW_DIR, f"view_{name}.png"), loc, target, (720, 720), lens)

    samples = {
        "run-loop": [0, 5, 10], "hook_cast": [7, 9, 13], "reel-loop": [0],
        "dragged-loop": [0], "death": [14, 36], "spawn": [6], "taunt": [14, 34],
    }
    for action_name, frames in samples.items():
        for frame in frames:
            use(action_name, frame)
            shot(os.path.join(PREVIEW_DIR, f"anim_{action_name}_{frame:02d}.png"), (4.2, -5.4, 2.4), (0, 0, 0.95), (360, 360))
    bpy.data.objects.remove(ground)


def main():
    reset_scene()
    material = vertex_color_material("HeroVertexColor")
    rig = build_rig("GaffRig", BONES)
    body, hook_in_hand = build_body()
    bind(rig, body, hook_in_hand)
    for obj in (body, hook_in_hand):
        obj.data.materials.append(material)
    build_animations(rig)

    hook = make_object("Hook", hook_mesh(scale=PROJECTILE_HOOK_SCALE), STEEL, sharp_angle=60)
    hook.data.materials.append(material)
    link = make_object("ChainLink", torus(0.05, 0.016, 10, 6, stretch=1.6), IRON)
    link.data.materials.append(material)

    print(f"TRIS hero={triangles(body) + triangles(hook_in_hand)} hook={triangles(hook)} link={triangles(link)}")

    os.makedirs(OUT_DIR, exist_ok=True)
    idle = bpy.data.actions["idle-loop"]
    rig.animation_data.action = idle
    rig.animation_data.action_slot = idle.slots[0]
    export_glb(os.path.join(OUT_DIR, "gaff.glb"), [rig, body, hook_in_hand], animations=True)
    export_glb(os.path.join(OUT_DIR, "hook.glb"), [hook], animations=False)
    export_glb(os.path.join(OUT_DIR, "chain_link.glb"), [link], animations=False)

    if PREVIEW_DIR:
        render_previews(rig, hidden=[hook, link])


if __name__ == "__main__":
    main()
