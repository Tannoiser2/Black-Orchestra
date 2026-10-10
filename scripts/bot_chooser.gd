extends RefCounted
class_name BOBotChooser
## Chooser automatico (casuale con qualche preferenza) usato per i test headless.

var rng := RandomNumberGenerator.new()
var plot_bias := true

func _init(seed_val: int = 1) -> void:
	rng.seed = seed_val

func choose(_p: int, _prompt: String, options: Array, _extra: Dictionary = {}) -> int:
	if options.is_empty():
		push_error("choose senza opzioni: " + _prompt)
		return 0
	return rng.randi_range(0, options.size() - 1)

func choose_space(_p: int, _prompt: String, spaces: Array, _cancel: bool) -> String:
	if spaces.is_empty():
		push_error("choose_space senza caselle: " + _prompt)
		return ""
	return spaces[rng.randi_range(0, spaces.size() - 1)]

func choose_action(_p: int, actions: Array) -> Dictionary:
	if plot_bias:
		for a in actions:
			if a.id == "plot":
				return a
	# scelta pesata: evita di terminare troppo presto
	var pick = actions[rng.randi_range(0, actions.size() - 1)]
	if pick.id == "end" and rng.randf() < 0.7 and actions.size() > 1:
		pick = actions[rng.randi_range(0, actions.size() - 2)]
	return pick

func notify(_t: String, _extra: Dictionary = {}) -> void:
	pass
