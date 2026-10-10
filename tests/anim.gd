extends SceneTree
func _initialize() -> void:
	root.size = Vector2i(1920, 1080)
	var g := BOGame.new()
	g.new_game([6, 15], 1, {}, 5)
	var b := BOBoardView.new()
	b.game = g
	root.add_child(b)
	g.moved.connect(b.on_moved)
	await process_frame
	g.s.stage = 5
	var start := Time.get_ticks_msec()
	g.move_consp(0, "SMOLENSK")
	g.move_leader("HITLER", "BERGHOF")
	print("busy subito: ", b.is_busy(), " tappe pedina: ", b.anim["P0"].queue.size())
	var mid_logged := false
	while b.is_busy():
		await process_frame
		if not mid_logged and Time.get_ticks_msec() - start > 400:
			print("a metà: pos ", b.anim["P0"].pos)
			mid_logged = true
	print("durata animazione ms: ", Time.get_ticks_msec() - start, "  pos finale ", b.anim["P0"].pos, " atteso ", b._token_target("P0"))
	quit()
