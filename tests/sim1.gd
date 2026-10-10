extends SceneTree
func _init() -> void:
	var game := BOGame.new()
	game.ch = BOBotChooser.new(7)
	game.logged.connect(func(t): print(t))
	game.new_game([0, 1], 1, {}, 1000)
	await game.run()
	quit()
