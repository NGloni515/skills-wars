import math

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree


def smoothstep(edge0, edge1, x):
    t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def reset_scene(fps=30):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = fps


def transform(bm, matrix):
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    return bm


def frustum(p0, p1, r0, r1, segments=12):
    p0, p1 = Vector(p0), Vector(p1)
    axis = p1 - p0
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=segments,
        radius1=r0, radius2=r1, depth=axis.length,
    )
    rotation = Vector((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
    return transform(bm, Matrix.Translation((p0 + p1) / 2) @ rotation)


def ellipsoid(center, size, u=20, v=12, rotation=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
    matrix = Matrix.Diagonal((*size, 1.0))
    if rotation is not None:
        matrix = rotation.to_matrix().to_4x4() @ matrix
    return transform(bm, Matrix.Translation(center) @ matrix)


def rounded_box(center, size, radius, segments=3):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    transform(bm, Matrix.Diagonal((*size, 1.0)))
    bmesh.ops.bevel(
        bm, geom=list(bm.edges) + list(bm.verts), offset=radius, segments=segments,
        profile=0.5, affect="EDGES", clamp_overlap=True,
    )
    return transform(bm, Matrix.Translation(center))


def polyline(points, steps):
    out = []
    for a, b in zip(points, points[1:]):
        a, b = Vector(a), Vector(b)
        out.extend(a.lerp(b, i / steps) for i in range(steps))
    out.append(Vector(points[-1]))
    return out


def tube(points, radii, sides=12, up=(0, 0, 1), caps=True):
    bm = bmesh.new()
    pts = [Vector(p) for p in points]
    up = Vector(up)
    rings = []
    for i, p in enumerate(pts):
        tangent = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        if abs(tangent.dot(up)) > 0.95:
            side = tangent.cross(Vector((1, 0, 0))).normalized()
        else:
            side = tangent.cross(up).normalized()
        normal = side.cross(tangent)
        r = radii[i] if isinstance(radii, (list, tuple)) else radii
        rings.append([
            bm.verts.new(p + r * (math.cos(a) * side + math.sin(a) * normal))
            for a in (2 * math.pi * k / sides for k in range(sides))
        ])
    for a, b in zip(rings, rings[1:]):
        for k in range(sides):
            bm.faces.new((a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]))
    if caps:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def torus(major, minor, u=16, v=8, center=(0, 0, 0), axis=(0, 0, 1), stretch=1.0):
    bm = bmesh.new()
    rings = []
    for i in range(u):
        a = 2 * math.pi * i / u
        radial = Vector((math.cos(a), math.sin(a), 0))
        ring_center = Vector((major * math.cos(a), major * math.sin(a) * stretch, 0))
        rings.append([
            bm.verts.new(ring_center + minor * (math.cos(b) * radial + math.sin(b) * Vector((0, 0, 1))))
            for b in (2 * math.pi * j / v for j in range(v))
        ])
    for i in range(u):
        a, b = rings[i], rings[(i + 1) % u]
        for j in range(v):
            bm.faces.new((a[j], b[j], b[(j + 1) % v], a[(j + 1) % v]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    rotation = Vector((0, 0, 1)).rotation_difference(Vector(axis).normalized()).to_matrix().to_4x4()
    return transform(bm, Matrix.Translation(center) @ rotation)


def lathe(radius_z_profile_at_angle, segments=32, closed_profile=True):
    profile_at = radius_z_profile_at_angle
    bm = bmesh.new()
    rings = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), z)) for r, z in profile_at(a)])
    count = len(rings[0])
    spans = count if closed_profile else count - 1
    for i in range(segments):
        a, b = rings[i], rings[(i + 1) % segments]
        for j in range(spans):
            bm.faces.new((a[j], b[j], b[(j + 1) % count], a[(j + 1) % count]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def merged(*parts):
    bm = bmesh.new()
    for part in parts:
        mesh = bpy.data.meshes.new("tmp")
        part.to_mesh(mesh)
        part.free()
        bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
    return bm


def _object_from(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def remeshed(parts, voxel_size, target_tris, smooth_iterations=4):
    obj = _object_from("remesh_tmp", merged(*parts))
    obj.data.remesh_voxel_size = voxel_size
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
        bpy.ops.object.voxel_remesh()
    smooth = obj.modifiers.new("Smooth", "SMOOTH")
    smooth.factor = 0.6
    smooth.iterations = smooth_iterations
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    bm.from_object(obj, depsgraph)
    bpy.data.objects.remove(obj)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    if len(bm.faces) > target_tris:
        decimate_obj = _object_from("decimate_tmp", bm)
        decimate = decimate_obj.modifiers.new("Decimate", "DECIMATE")
        decimate.ratio = target_tris / len(decimate_obj.data.polygons)
        bm = bmesh.new()
        bm.from_object(decimate_obj, bpy.context.evaluated_depsgraph_get())
        bpy.data.objects.remove(decimate_obj)
    return bm


def bvh(bm):
    return BVHTree.FromBMesh(bm)


def rigid(bone):
    return lambda co: {bone: 1.0}


def blend_along(a, b, joint, bone_a, bone_b, width):
    direction = (Vector(b) - Vector(a)).normalized()
    joint = Vector(joint)

    def weights(co):
        w = smoothstep(-width, width, (co - joint).dot(direction))
        return {bone_a: 1.0 - w, bone_b: w}

    return weights


def make_object(name, bm, color, weights=None, sharp_angle=None):
    for face in bm.faces:
        face.smooth = True
    if sharp_angle is not None:
        limit = math.radians(sharp_angle)
        for edge in bm.edges:
            if len(edge.link_faces) == 2 and edge.calc_face_angle(0.0) > limit:
                edge.smooth = False
    obj = _object_from(name, bm)
    mesh = obj.data
    attr = mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    for item in attr.data:
        item.color_srgb = (*color, 1.0)
    if weights is not None:
        if isinstance(weights, str):
            weights = rigid(weights)
        groups = {}
        for v in mesh.vertices:
            for bone, w in weights(v.co).items():
                if w <= 1e-4:
                    continue
                if bone not in groups:
                    groups[bone] = obj.vertex_groups.new(name=bone)
                groups[bone].add([v.index], w, "REPLACE")
    return obj


def join(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    result = bpy.context.view_layer.objects.active
    result.name = name
    result.data.name = name
    result.data.color_attributes.active_color = result.data.color_attributes["Col"]
    return result


def triangles(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def vertex_color_material(name="VertexColor"):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.8
    color = nodes.new("ShaderNodeVertexColor")
    color.layer_name = "Col"
    mat.node_tree.links.new(color.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def build_rig(name, bones):
    data = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, head, tail, parent in bones:
        bone = data.edit_bones.new(bone_name)
        bone.head, bone.tail, bone.roll = head, tail, 0.0
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.animation_data_create()
    return rig


def bind(rig, *meshes):
    for obj in meshes:
        obj.parent = rig
        obj.modifiers.new("Armature", "ARMATURE").object = rig


def export_glb(path, objects, animations):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_animations=animations,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_skins=animations,
        export_vertex_color="ACTIVE",
    )
