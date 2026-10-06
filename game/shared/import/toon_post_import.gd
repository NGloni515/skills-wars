@tool
extends EditorScenePostImport

const TOON_SOFTNESS := 0.45


func _post_import(scene: Node) -> Object:
	for mesh_instance: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(i) as BaseMaterial3D
			if material:
				material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				material.roughness = TOON_SOFTNESS
	return scene
