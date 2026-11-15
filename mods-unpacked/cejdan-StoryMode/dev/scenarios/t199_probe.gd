extends "res://mods-unpacked/cejdan-StoryMode/dev/scenario.gd"

# Ticket 199 probe: do float SubViewports work under this renderer, and do
# values survive a write and a read through a canvas shader unchanged?

func boot() -> Dictionary:
	return {"seed": 12345}


func _vp(hdr: bool, code: String, tex = null) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(8, 8)
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.use_hdr_2d = hdr
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var r := ColorRect.new()
	r.size = Vector2(8, 8)
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	if tex != null:
		m.set_shader_parameter("prev", tex)
	r.material = m
	vp.add_child(r)
	Level.map.add_child(vp)
	return vp


func run(h) -> void:
	h.disable_waves()
	var write := "shader_type canvas_item;\nrender_mode blend_disabled;\nvoid fragment(){ COLOR = vec4(0.25, -0.5, 2.0, 0.3); }"
	var copy := "shader_type canvas_item;\nrender_mode blend_disabled;\nuniform sampler2D prev : filter_linear, repeat_disable;\nvoid fragment(){ COLOR = texture(prev, UV); }"
	for hdr in [true, false]:
		var a := _vp(hdr, write)
		var b := _vp(hdr, copy, a.get_texture())
		await h.frames(5)
		var ia: Image = a.get_texture().get_image()
		var ib: Image = b.get_texture().get_image()
		h.note("hdr=%s" % hdr, {"format_a": ia.get_format(), "a": str(ia.get_pixel(3, 3)), "format_b": ib.get_format(), "b": str(ib.get_pixel(3, 3))})
	h.note("renderer", {"method": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), "adapter": RenderingServer.get_video_adapter_name(),
		"zoom": str(get_viewport_zoom()), "vis": str(Level.map.get_viewport().get_visible_rect())})


func get_viewport_zoom():
	var cam = Level.map.get_viewport().get_camera_2d()
	return cam.zoom if cam != null else null
