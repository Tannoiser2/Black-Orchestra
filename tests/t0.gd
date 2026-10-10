extends SceneTree
func _init() -> void:
	print("hello")
	var g = BOGame.new()
	print("game ok ", g.berlin.size())
	quit()
