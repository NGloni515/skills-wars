import math
import os
import random
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from river_arena_shape import (
    HALF_X, HALF_Z, PLAY_HALF_X, PLAY_HALF_Z, RIVER_EDGE, WATER_HALF_WIDTH, WATER_LEVEL, WATER_PLANE_HALF_WIDTH, height,
)

OUT_PATH = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else "game/maps/river_arena/river_arena.tscn"
NATURE = "res://maps/shared/nature/"
WALL = 0.5
BANK = PLAY_HALF_X - RIVER_EDGE

# (model, distance into the west bank as a fraction, z as a fraction of the half length, yaw in degrees).
# East rocks are the same rocks turned half a turn around the center, so both teams get the same cover.
ROCKS = [
    ("rock_1", 0.241, -0.533, 116.6),
    ("rock_2", 0.448, 0.333, 54.3),
    ("rock_3", 0.138, 0.667, -125.7),
    ("rock_1", 0.655, -0.133, 26.1),
]
SPAWN_BANK_FRACTION = 0.793
SPAWN_Z_FRACTIONS = [-0.4, 0.0, 0.4]
TREES = ["tree_1", "tree_2", "tree_3", "pine_1", "pine_2"]
BUSHES = ["bush", "bush_flowers"]

EXT = {
    "script": ("Script", "res://maps/river_arena/river_arena.gd"),
    "terrain": ("PackedScene", "res://maps/river_arena/terrain.glb"),
    "terrain_shader": ("Shader", "res://maps/shared/terrain.gdshader"),
    "water_shader": ("Shader", "res://maps/shared/water.gdshader"),
    "scatter": ("Script", "res://maps/shared/prop_scatter.gd"),
    "rock_1": ("PackedScene", NATURE + "Rock_Medium_1.gltf"),
    "rock_2": ("PackedScene", NATURE + "Rock_Medium_2.gltf"),
    "rock_3": ("PackedScene", NATURE + "Rock_Medium_3.gltf"),
    "tree_1": ("PackedScene", NATURE + "CommonTree_1.gltf"),
    "tree_2": ("PackedScene", NATURE + "CommonTree_2.gltf"),
    "tree_3": ("PackedScene", NATURE + "CommonTree_3.gltf"),
    "pine_1": ("PackedScene", NATURE + "Pine_1.gltf"),
    "pine_2": ("PackedScene", NATURE + "Pine_2.gltf"),
    "bush": ("PackedScene", NATURE + "Bush_Common.gltf"),
    "bush_flowers": ("PackedScene", NATURE + "Bush_Common_Flowers.gltf"),
    "fern": ("PackedScene", NATURE + "Fern_1.gltf"),
    "flower_group": ("PackedScene", NATURE + "Flower_4_Group.gltf"),
    "plant": ("PackedScene", NATURE + "Plant_1.gltf"),
    "mushroom": ("PackedScene", NATURE + "Mushroom_Common.gltf"),
    "grass": ("PackedScene", NATURE + "Grass_Common_Short.gltf"),
    "wispy_grass": ("PackedScene", NATURE + "Grass_Wispy_Short.gltf"),
    "flowers": ("PackedScene", NATURE + "Flower_3_Group.gltf"),
    "pebble_1": ("PackedScene", NATURE + "Pebble_Round_1.gltf"),
    "pebble_3": ("PackedScene", NATURE + "Pebble_Round_3.gltf"),
}


def num(value):
    return f"{value:.4f}".rstrip("0").rstrip(".") if value != 0 else "0"


def xform(x, y, z, yaw_degrees=0.0, scale=1.0):
    c = math.cos(math.radians(yaw_degrees)) * scale
    s = math.sin(math.radians(yaw_degrees)) * scale
    values = [c, 0, s, 0, scale, 0, -s, 0, c, x, y, z]
    return "Transform3D(" + ", ".join(num(v) for v in values) + ")"


def node(name, kind=None, parent=None, instance=None, groups=None, **props):
    header = f'[node name="{name}"'
    if kind:
        header += f' type="{kind}"'
    if parent is not None:
        header += f' parent="{parent}"'
    if instance:
        header += f' instance=ExtResource("{instance}")'
    if groups:
        header += " groups=[" + ", ".join(f'"{g}"' for g in groups) + "]"
    lines = [header + "]"]
    lines += [f"{key} = {value}" for key, value in props.items()]
    return "\n".join(lines)


def ground_y(x, z):
    return round(height(x, z), 3)


def scenery(rng):
    items = []

    def add(kind, x, z, scale):
        if abs(x) < RIVER_EDGE + 0.9:
            x = math.copysign(RIVER_EDGE + 0.9, x)
        items.append((kind, x, ground_y(x, z), z, rng.uniform(-180, 180), scale))

    for i in range(8):
        x = -HALF_X + 5 + i * (2 * HALF_X - 12) / 7 + rng.uniform(-1.2, 1.2)
        add(rng.choice(TREES), x, -(PLAY_HALF_Z + rng.uniform(3.0, 6.4)), rng.uniform(0.8, 0.96))
    for side in (-1, 1):
        for fraction in (-0.8, -0.35, 0.3):
            z = fraction * PLAY_HALF_Z + rng.uniform(-1.0, 1.0)
            add(rng.choice(TREES), side * (PLAY_HALF_X + rng.uniform(4.5, 5.6)), z, rng.uniform(0.8, 0.92))
        for fraction in (-1.05, -0.57, 0.05, 0.6, 0.9):
            z = fraction * PLAY_HALF_Z + rng.uniform(-0.6, 0.6)
            add(rng.choice(BUSHES), side * (PLAY_HALF_X + rng.uniform(1.6, 2.9)), z, rng.uniform(1.0, 1.3))
    for i in range(10):
        x = -HALF_X + 6 + i * (2 * HALF_X - 12) / 9 + rng.uniform(-0.8, 0.8)
        add(rng.choice(BUSHES), x, PLAY_HALF_Z + rng.uniform(2.9, 4.0), rng.uniform(0.92, 1.2))
    for fraction in (-1.25, -0.45, 0.42, 1.35):
        add(rng.choice(BUSHES), fraction * PLAY_HALF_X, -(PLAY_HALF_Z + rng.uniform(1.5, 2.0)), rng.uniform(1.1, 1.2))
    return items


def scatter(name, source, count_per_m2, area, keep_out, scale_range, seed):
    x, z, w, d = area
    count = max(4, round(count_per_m2 * w * d))
    return node(
        name, "MultiMeshInstance3D", "Decor",
        script='ExtResource("scatter")', source=f'ExtResource("{source}")', count=count,
        area=f"Rect2({num(x)}, {num(z)}, {num(w)}, {num(d)})", keep_out_half_width=num(keep_out),
        scale_range=f"Vector2({num(scale_range[0])}, {num(scale_range[1])})", random_seed=seed,
    )


def build():
    rng = random.Random(7)
    resources = [f'[ext_resource type="{kind}" path="{path}" id="{key}"]' for key, (kind, path) in EXT.items()]
    sub = f"""[sub_resource type="Environment" id="Environment_main"]
background_mode = 1
background_color = Color(0.56, 0.78, 0.93, 1)
ambient_light_source = 2
ambient_light_color = Color(0.7, 0.78, 0.92, 1)
ambient_light_energy = 0.5
tonemap_mode = 2
tonemap_exposure = 1.0
glow_enabled = true
glow_intensity = 0.15
glow_bloom = 0.04
adjustment_enabled = true
adjustment_contrast = 1.06
adjustment_saturation = 1.05

[sub_resource type="ShaderMaterial" id="Mat_terrain"]
render_priority = 0
shader = ExtResource("terrain_shader")
shader_parameter/arena_half_size = Vector2({num(PLAY_HALF_X)}, {num(PLAY_HALF_Z)})

[sub_resource type="ShaderMaterial" id="Mat_water"]
render_priority = 0
shader = ExtResource("water_shader")

[sub_resource type="PlaneMesh" id="Mesh_water"]
material = SubResource("Mat_water")
size = Vector2({num(WATER_PLANE_HALF_WIDTH * 2)}, {num(HALF_Z * 2)})
subdivide_width = 8
subdivide_depth = 64

[sub_resource type="BoxShape3D" id="Shape_bank"]
size = Vector3({num(BANK)}, 1, {num(PLAY_HALF_Z * 2)})

[sub_resource type="BoxShape3D" id="Shape_river_edge"]
size = Vector3({num(WALL)}, 3, {num(PLAY_HALF_Z * 2)})

[sub_resource type="BoxShape3D" id="Shape_side_wall"]
size = Vector3({num(WALL)}, 3, {num(PLAY_HALF_Z * 2 + 1)})

[sub_resource type="BoxShape3D" id="Shape_end_wall"]
size = Vector3({num(PLAY_HALF_X * 2 + 1)}, 3, {num(WALL)})

[sub_resource type="CylinderShape3D" id="Shape_rock"]
height = 2.0
radius = 0.95"""
    nodes = [
        node("RiverArena", "Node3D", script='ExtResource("script")', terrain_material='SubResource("Mat_terrain")',
             water_half_width=num(WATER_HALF_WIDTH), water_level=num(WATER_LEVEL)),
        node("Sun", "DirectionalLight3D", ".",
             transform="Transform3D(0.8192, -0.4698, 0.329, 0, 0.5736, 0.8192, -0.5736, -0.671, 0.4698, 0, 10, 0)",
             light_color="Color(1, 0.95, 0.86, 1)", light_energy="1.05", shadow_enabled="true",
             directional_shadow_mode="1", directional_shadow_max_distance="45.0"),
        node("WorldEnvironment", "WorldEnvironment", ".", environment='SubResource("Environment_main")'),
        node("Terrain", parent=".", instance="terrain"),
        node("Water", "MeshInstance3D", ".", transform=xform(0, WATER_LEVEL, 0), cast_shadow="0",
             mesh='SubResource("Mesh_water")'),
        node("Ground", "StaticBody3D", ".", collision_mask="0"),
    ]
    bank_center = RIVER_EDGE + BANK / 2
    for name, side in (("BankWest", -1), ("BankEast", 1)):
        nodes.append(node(name, "CollisionShape3D", "Ground", transform=xform(side * bank_center, -0.5, 0),
                          shape='SubResource("Shape_bank")'))
    nodes.append(node("HeroWalls", "StaticBody3D", ".", collision_layer="2", collision_mask="0"))
    walls = [
        ("RiverEdgeWest", -(RIVER_EDGE - WALL / 2), 0, "Shape_river_edge"),
        ("RiverEdgeEast", RIVER_EDGE - WALL / 2, 0, "Shape_river_edge"),
        ("WestWall", -(PLAY_HALF_X + WALL / 2), 0, "Shape_side_wall"),
        ("EastWall", PLAY_HALF_X + WALL / 2, 0, "Shape_side_wall"),
        ("NorthWall", 0, -(PLAY_HALF_Z + WALL / 2), "Shape_end_wall"),
        ("SouthWall", 0, PLAY_HALF_Z + WALL / 2, "Shape_end_wall"),
    ]
    for name, x, z, shape in walls:
        nodes.append(node(name, "CollisionShape3D", "HeroWalls", transform=xform(x, 1, z), shape=f'SubResource("{shape}")'))

    for group in ("Rocks", "Scenery", "Decor", "Spawns"):
        nodes.append(node(group, "Node3D", "."))
    spawn_x = RIVER_EDGE + SPAWN_BANK_FRACTION * BANK
    for i, fraction in enumerate(SPAWN_Z_FRACTIONS):
        z = fraction * PLAY_HALF_Z
        nodes.append(node(f"West{i + 1}", "Marker3D", "Spawns", groups=["spawn_team_0"],
                          transform=f"Transform3D(0, 0, 1, 0, 1, 0, -1, 0, 0, {num(-spawn_x)}, 0, {num(z)})"))
    for i, fraction in enumerate(SPAWN_Z_FRACTIONS):
        z = fraction * PLAY_HALF_Z
        nodes.append(node(f"East{i + 1}", "Marker3D", "Spawns", groups=["spawn_team_1"],
                          transform=f"Transform3D(0, 0, -1, 0, 1, 0, 1, 0, 0, {num(spawn_x)}, 0, {num(z)})"))

    for i, (model, bank_fraction, z_fraction, yaw) in enumerate(ROCKS):
        x = RIVER_EDGE + bank_fraction * BANK
        z = z_fraction * PLAY_HALF_Z
        for name, sx, sz, turn in ((f"RockW{i + 1}", -x, z, 0.0), (f"RockE{i + 1}", x, -z, 180.0)):
            path = f"Rocks/{name}"
            nodes.append(node(name, "StaticBody3D", "Rocks", transform=xform(sx, 0, sz),
                              collision_layer="6", collision_mask="0"))
            nodes.append(node("Model", parent=path, instance=model, transform=xform(0, -0.12, 0, yaw + turn, 0.62)))
            nodes.append(node("Shape", "CollisionShape3D", path, transform=xform(0, 0.6, 0), shape='SubResource("Shape_rock")'))

    for i, (kind, x, y, z, yaw, scale) in enumerate(scenery(rng)):
        nodes.append(node(f"{kind}_{i}", parent="Scenery", instance=kind, transform=xform(x, y, z, yaw, scale)))

    corner_x, corner_z = PLAY_HALF_X - 1.5, PLAY_HALF_Z - 1.5
    decor = [
        ("fern", -corner_x, -corner_z, 100.6, 0.6), ("fern", corner_x, corner_z, 93.3, 0.6),
        ("flower_group", -(PLAY_HALF_X - 1.2), PLAY_HALF_Z - 1.8, -110.7, 0.4),
        ("flower_group", PLAY_HALF_X - 1.2, -(PLAY_HALF_Z - 1.8), -15.6, 0.4),
        ("plant", -(RIVER_EDGE + 1.1), -(PLAY_HALF_Z - 1.0), 161.0, 0.7),
        ("plant", RIVER_EDGE + 1.1, PLAY_HALF_Z - 1.0, -22.7, 0.7),
        ("mushroom", -(PLAY_HALF_X - 1.0), 0.17 * PLAY_HALF_Z, -4.3, 1.2),
        ("mushroom", PLAY_HALF_X - 1.0, -0.17 * PLAY_HALF_Z, -16.2, 1.2),
    ]
    for i, (kind, x, z, yaw, scale) in enumerate(decor):
        nodes.append(node(f"{kind}_{i}", parent="Decor", instance=kind, transform=xform(x, 0, z, yaw, scale)))

    lawn = (-(PLAY_HALF_X - 0.5), -(PLAY_HALF_Z - 0.5), 2 * (PLAY_HALF_X - 0.5), 2 * (PLAY_HALF_Z - 0.5))
    beds = (-(PLAY_HALF_X - 1), -(PLAY_HALF_Z - 1), 2 * (PLAY_HALF_X - 1), 2 * (PLAY_HALF_Z - 1))
    shore = (-(RIVER_EDGE + 1.4), -PLAY_HALF_Z, 2 * (RIVER_EDGE + 1.4), 2 * PLAY_HALF_Z)
    nodes += [
        scatter("Grass", "grass", 0.108, lawn, RIVER_EDGE + 0.8, (0.3, 0.42), 11),
        scatter("WispyGrass", "wispy_grass", 0.059, lawn, RIVER_EDGE + 0.8, (0.28, 0.38), 12),
        scatter("Flowers", "flowers", 0.017, beds, RIVER_EDGE + 1.5, (0.25, 0.32), 13),
        scatter("ShorePebbles", "pebble_1", 0.088, shore, RIVER_EDGE + 0.25, (1.0, 1.8), 14),
        scatter("ShorePebbles2", "pebble_3", 0.075, shore, RIVER_EDGE + 0.25, (0.9, 1.6), 15),
    ]

    load_steps = len(EXT) + sub.count("[sub_resource") + 1
    text = f"[gd_scene load_steps={load_steps} format=3]\n\n" + "\n".join(resources) + "\n\n" + sub + "\n\n"
    text += "\n\n".join(nodes) + "\n"
    with open(OUT_PATH, "w") as out:
        out.write(text)
    print(f"wrote {OUT_PATH}: play area {PLAY_HALF_X * 2:.1f} x {PLAY_HALF_Z * 2:.1f} m, river {RIVER_EDGE * 2:.2f} m")


build()
