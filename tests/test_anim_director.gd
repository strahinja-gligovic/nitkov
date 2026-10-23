extends GutTest
## AnimDirector's pure helpers.

const DIAMOND := [Vector2(4, 0), Vector2(0, 6), Vector2(-4, 0), Vector2(0, -3)]


func test_ray_reaches_the_points_themselves() -> void:
	var hull := Geometry2D.convex_hull(PackedVector2Array(DIAMOND))
	assert_almost_eq(AnimDirector.ray_to_polygon(Vector2(0, 1), hull), 6.0, 0.001)
	assert_almost_eq(AnimDirector.ray_to_polygon(Vector2(1, 0), hull), 4.0, 0.001)
	assert_almost_eq(AnimDirector.ray_to_polygon(Vector2(0, -1), hull), 3.0, 0.001)


func test_ray_between_points_hits_the_edge() -> void:
	var hull := Geometry2D.convex_hull(PackedVector2Array(DIAMOND))
	# the edge from (4,0) to (0,6): x/4 + y/6 = 1 -> along the diagonal t/4 + t/6 = 1/sqrt(2)... solve directly
	var dir := Vector2(1, 1).normalized()
	var t := AnimDirector.ray_to_polygon(dir, hull)
	var p := dir * t
	assert_almost_eq(p.x / 4.0 + p.y / 6.0, 1.0, 0.001)


func test_ray_misses_an_empty_polygon() -> void:
	assert_eq(AnimDirector.ray_to_polygon(Vector2.UP, PackedVector2Array()), 0.0)
