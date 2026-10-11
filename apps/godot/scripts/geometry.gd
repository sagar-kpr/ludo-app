extends RefCounted

static func beveled_pin(outline: Array[Vector2], depth: float, bevel: float = 0.04) -> ImmediateMesh:
	var base := extruded_outline(outline,depth-bevel*2,true)
	var arrays := base.surface_get_arrays(0)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(arrays[Mesh.ARRAY_VERTEX].size()):
		mesh.surface_set_normal(arrays[Mesh.ARRAY_NORMAL][index])
		mesh.surface_add_vertex(arrays[Mesh.ARRAY_VERTEX][index])
	var inner: Array[Vector2] = []
	for point in outline:
		inner.append(Vector2(0,0.88)+(point-Vector2(0,0.88))*0.90)
	var indices := Geometry2D.triangulate_polygon(PackedVector2Array(inner))
	for offset in range(0,indices.size(),3):
		var points: Array[Vector3] = []
		for index in range(3):
			var p := inner[indices[offset+index]]
			points.append(Vector3(p.x,p.y,depth/2))
		if (points[1]-points[0]).cross(points[2]-points[0]).z > 0:
			points.reverse()
		mesh.surface_set_normal(Vector3.BACK)
		for point in points:
			mesh.surface_add_vertex(point)
	for index in range(outline.size()):
		var next := (index+1)%outline.size()
		var a := outline[index]
		var b := outline[next]
		var c := inner[next]
		var d := inner[index]
		var edge := b-a
		var normal := Vector3(edge.y,-edge.x,edge.length()).normalized()
		var points := [Vector3(a.x,a.y,depth/2-bevel),Vector3(b.x,b.y,depth/2-bevel),Vector3(c.x,c.y,depth/2),Vector3(d.x,d.y,depth/2)]
		var order := [0,2,1,0,3,2] if (points[1]-points[0]).cross(points[2]-points[0]).dot(normal)>0 else [0,1,2,0,2,3]
		mesh.surface_set_normal(normal)
		for vertex in order:
			mesh.surface_add_vertex(points[vertex])
	mesh.surface_end()
	return mesh

static func rounded_slab(dimensions: Vector3, radius: float = 0.2) -> ImmediateMesh:
	# Rounded footprint independent of slab thickness, unlike a beveled cube.
	var outline: Array[Vector2] = []
	var half := Vector2(dimensions.x,dimensions.z)*0.5
	var r := minf(radius,minf(half.x,half.y)*0.95)
	for corner in range(4):
		var angle := corner*PI/2.0
		var center := Vector2(half.x-r,half.y-r)*Vector2(1 if corner in [0,3] else -1,1 if corner < 2 else -1)
		for step in range(7):
			var a := angle+step*PI/12.0
			outline.append(center+Vector2(cos(a),sin(a))*r)
	# A sloped top lip catches the key light; the vertical skirt stays darker.
	var bevel := minf(0.10,dimensions.y*0.3)
	var base := extruded_outline(outline,dimensions.y-bevel)
	var arrays := base.surface_get_arrays(0)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(arrays[Mesh.ARRAY_VERTEX].size()):
		mesh.surface_set_normal(arrays[Mesh.ARRAY_NORMAL][index])
		mesh.surface_add_vertex(arrays[Mesh.ARRAY_VERTEX][index]-Vector3.UP*bevel*0.5)
	var inner: Array[Vector2] = []
	for point in outline:
		inner.append(point*Vector2((half.x-bevel)/half.x,(half.y-bevel)/half.y))
	var indices := Geometry2D.triangulate_polygon(PackedVector2Array(inner))
	for offset in range(0,indices.size(),3):
		var points: Array[Vector3] = []
		for i in range(3):
			var p := inner[indices[offset+i]]
			points.append(Vector3(p.x,dimensions.y*0.5,p.y))
		if (points[1]-points[0]).cross(points[2]-points[0]).y > 0:
			points.reverse()
		mesh.surface_set_normal(Vector3.UP)
		for point in points:
			mesh.surface_add_vertex(point)
	for i in range(outline.size()):
		var next := (i+1)%outline.size()
		var a := outline[i]
		var b := outline[next]
		var c := inner[next]
		var d := inner[i]
		var edge := b-a
		var normal := Vector3(edge.y,edge.length(),-edge.x).normalized()
		var points := [Vector3(a.x,dimensions.y*0.5-bevel,a.y),Vector3(b.x,dimensions.y*0.5-bevel,b.y),Vector3(c.x,dimensions.y*0.5,c.y),Vector3(d.x,dimensions.y*0.5,d.y)]
		var order := [0,2,1,0,3,2] if (points[1]-points[0]).cross(points[2]-points[0]).dot(normal)>0 else [0,1,2,0,2,3]
		mesh.surface_set_normal(normal)
		for vertex in order:
			mesh.surface_add_vertex(points[vertex])
	mesh.surface_end()
	return mesh

static func extruded_outline(outline: Array[Vector2], depth: float, upright: bool = false) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles := Geometry2D.triangulate_polygon(PackedVector2Array(outline))
	var normal := Vector3.BACK if upright else Vector3.UP
	for side in [-1,1]:
		for offset in range(0,triangles.size(),3):
			var points: Array[Vector3] = []
			for index in range(3):
				var p := outline[triangles[offset+index]]
				points.append(Vector3(p.x,p.y,side*depth/2) if upright else Vector3(p.x,side*depth/2,p.y))
			if (points[1]-points[0]).cross(points[2]-points[0]).dot(normal*side) > 0:
				points.reverse()
			mesh.surface_set_normal(normal*side)
			for point in points:
				mesh.surface_add_vertex(point)
	for index in range(outline.size()):
		var a := outline[index]
		var b := outline[(index+1)%outline.size()]
		var edge := b-a
		var outward := Vector2(edge.y,-edge.x).normalized()
		var n := Vector3(outward.x,outward.y,0) if upright else Vector3(outward.x,0,outward.y)
		var points: Array[Vector3] = []
		for pair in [Vector3(a.x,a.y,1),Vector3(b.x,b.y,1),Vector3(b.x,b.y,-1),Vector3(a.x,a.y,-1)]:
			points.append(Vector3(pair.x,pair.y,pair.z*depth/2) if upright else Vector3(pair.x,pair.z*depth/2,pair.y))
		var order := [0,2,1,0,3,2] if (points[1]-points[0]).cross(points[2]-points[0]).dot(n) > 0 else [0,1,2,0,2,3]
		mesh.surface_set_normal(n)
		for vertex in order:
			mesh.surface_add_vertex(points[vertex])
	mesh.surface_end()
	return mesh

static func bevel_box(dimensions: Vector3, bevel: float = 0.06) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := dimensions * 0.5
	var radius := minf(bevel, minf(half.x,minf(half.y,half.z))*0.8)
	var inner_max := half-Vector3.ONE*radius
	var faces := [
		[Vector3.UP,Vector3.RIGHT,Vector3.FORWARD], [Vector3.DOWN,Vector3.RIGHT,Vector3.BACK],
		[Vector3.RIGHT,Vector3.BACK,Vector3.UP], [Vector3.LEFT,Vector3.FORWARD,Vector3.UP],
		[Vector3.FORWARD,Vector3.RIGHT,Vector3.UP], [Vector3.BACK,Vector3.LEFT,Vector3.UP]
	]
	for face in faces:
		var order := [0,2,1,0,3,2] if face[1].cross(face[2]).dot(face[0]) > 0 else [0,1,2,0,2,3]
		var width: float = (face[1]*dimensions).length()
		var height: float = (face[2]*dimensions).length()
		var xs := [-0.5, -0.5+radius/width, 0.5-radius/width, 0.5]
		var ys := [-0.5, -0.5+radius/height, 0.5-radius/height, 0.5]
		for row in range(3):
			for col in range(3):
				var corners := [Vector2(xs[col],ys[row]),Vector2(xs[col+1],ys[row]),Vector2(xs[col+1],ys[row+1]),Vector2(xs[col],ys[row+1])]
				# Godot uses clockwise front faces. Keep surface normals facing out.
				for index in order:
					var grid: Vector2 = corners[index]
					var raw: Vector3 = face[0]*half + face[1]*grid.x*width + face[2]*grid.y*height
					var inner := raw.clamp(-inner_max,inner_max)
					var normal := (raw-inner).normalized()
					mesh.surface_set_normal(normal)
					mesh.surface_add_vertex(inner+normal*radius)
	mesh.surface_end()
	return mesh

static func lathe(profile: Array[Vector2], segments: int = 32) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(profile.size()-1):
		var slope := (profile[row+1].x-profile[row].x) / maxf(0.001,profile[row+1].y-profile[row].y)
		for segment in range(segments):
			for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				var angle: float = (segment+corner.x)*TAU/segments
				var p: Vector2 = profile[row+corner.y]
				mesh.surface_set_normal(Vector3(cos(angle),-slope,sin(angle)).normalized())
				mesh.surface_add_vertex(Vector3(cos(angle)*p.x,p.y,sin(angle)*p.x))
	mesh.surface_end()
	return mesh
