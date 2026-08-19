extends GameHooks
## The Barred Gate's entire code.
##
## Everything else this game is - five maps, a gate that wants a key, a lantern that wants
## oil, nine conversations, its own palette - is data. What is left is the one thing data
## cannot say: the warden has three lines, and which one she uses depends on what the player
## is carrying and what they have done with it.
##
## Note what is NOT here. No autoload is named: this file reads the GameContext it is handed,
## which is what keeps it inside the per-file parse gate and the whole-project compile (both
## skip any script that mentions a singleton). No colour, no direction string, no unseeded
## random - a game promises those the same way the template does.
##
## And note the `return false`. It is not a fallback, it is the design: the hook takes the
## two cases it has something to say about and lets the map's own `dialog` handle the rest,
## so adding a line to the warden's opening never touches this file.

## Handed over by the stash in quest_hollow, wanted by the gate in quest_village. The map
## declares both halves; this file reads it only to choose which line the warden says.
const ITEM_KEY := &"gate_key"
## Set by the lantern in quest_keep. This is the only flag the game reads rather than just
## carrying, because it is the one the ending is made of.
const FLAG_LIT := &"lit_the_lantern"

const WARDEN := &"warden"


func on_interact(ctx: GameContext, target: Interactor.Target) -> bool:
	if target.id != WARDEN:
		return false
	if ctx.has_flag(FLAG_LIT):
		ctx.say(&"warden_thanks")
		return true
	if ctx.has_item(ITEM_KEY):
		ctx.say(&"warden_has_key")
		return true
	# She has nothing new to say, and the map already names the line she opens with.
	return false


## Content this game is responsible for, checked by the same gate that validates the
## template's maps and manifests - a game's own faults should fail the build the way the
## template's do, not wait to be noticed in play.
func problems() -> Array[String]:
	var out: Array[String] = []
	for dialog_id in [&"warden_has_key", &"warden_thanks"]:
		# These two are named HERE and nowhere in data, so nothing else can notice them
		# going missing: a rename would leave the warden silent exactly when she has
		# something to say, which reads as the quest not having advanced.
		if not FileAccess.file_exists("res://data/dialog/%s.json" % dialog_id):
			out.append("hooks name dialog '%s', which does not exist" % dialog_id)
	# Same reasoning for the item: it is named here as a bare id, so a rename in data/items
	# would leave this file asking about something nobody carries, and the warden goes quiet.
	if not FileAccess.file_exists("res://data/items/%s.tres" % ITEM_KEY):
		out.append("hooks name item '%s', which does not exist" % ITEM_KEY)
	return out
