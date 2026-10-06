import math

import bpy
from mathutils import Quaternion, Vector

AXES = {"x": Vector((1, 0, 0)), "y": Vector((0, 1, 0)), "z": Vector((0, 0, 1))}


def rot(x=0.0, y=0.0, z=0.0, loc=None):
    spec = {"rot": [(axis, deg) for axis, deg in (("x", x), ("y", y), ("z", z)) if deg]}
    if loc:
        spec["loc"] = loc
    return spec


def mirror(pose):
    def flip(name):
        return name[:-1] + {"L": "R", "R": "L"}[name[-1]] if name[-2:] in (".L", ".R") else name

    out = {}
    for name, spec in pose.items():
        flipped = {"rot": [(a, d if a == "x" else -d) for a, d in spec["rot"]]}
        if "loc" in spec:
            x, y, z = spec["loc"]
            flipped["loc"] = (-x, y, z)
        out[flip(name)] = flipped
    return out


def with_pose(base, **changes):
    pose = dict(base)
    for name, spec in changes.items():
        pose[name.replace("_L", ".L").replace("_R", ".R")] = spec
    return pose


def apply_pose(rig, pose):
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    for name, spec in pose.items():
        pb = rig.pose.bones[name]
        to_local = pb.bone.matrix_local.to_3x3().inverted()
        q = Quaternion()
        for axis, deg in spec["rot"]:
            q = Quaternion((to_local @ AXES[axis]).normalized(), math.radians(deg)) @ q
        pb.rotation_quaternion = q
        if "loc" in spec:
            pb.location = to_local @ Vector(spec["loc"])


def add_action(rig, name, keys, loop=False):
    action = bpy.data.actions.new(name + ("-loop" if loop else ""))
    action.use_fake_user = True
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots.new(id_type="OBJECT", name=rig.name)
    for frame, pose in keys:
        apply_pose(rig, pose)
        for pb in rig.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            pb.keyframe_insert("location", frame=frame)
    return action
