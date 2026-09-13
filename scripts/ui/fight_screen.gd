class_name FightScreen
extends CanvasLayer
## What every screen that resolves a fight is, whichever resolver draws it.
##
## The world opens a fight through ONE seam and hears back through ONE signal, and since M50 two
## screens answer it: BattleScreen, the menu fight, and ArenaScreen, the sword. Everything the world
## relies on of either lives here, so a third resolver cannot be half a fight screen - the two
## signals, the layer, the latch that stops a result going out twice, the formation cap a map record
## is held to, and how big a fighter is drawn.

## A sound this view wants played. Emitted rather than played directly, for two reasons.
##
## Signals up, calls down - the world owns the speaker, and a view asking for a noise is the
## same shape as a view asking for anything else. And practically: check.sh's per-file parse
## gate skips any file whose TEXT names an autoload, so calling the audio singleton here would
## quietly drop this file out of that gate, along with every test that depends on it. That is
## not hypothetical - it is how this signal came to exist. Do not name it in prose either.
signal sound_wanted(id: StringName)

## The fight is over: a BattleLogic.Outcome and the effects the world applies. Emitted once.
signal finished(outcome: int, effects: Array)

const LAYER := 12

## How many foes a fight screen draws, and therefore how large a formation a map record may name.
## Three: what BattleScreen's banner names on one line at the widest names its layout audit uses,
## and the size the genre's own small fights come in. On the base rather than on one screen,
## because a formation is a MAP rule - the same record opens either resolver.
const MAX_FOES := 3

## Set the frame the result goes out, and never cleared. Without it _physics_process emits
## again on every later frame - the fight is still finished - and the world applies the same
## xp, the same seen key and the same item take once per frame until something notices.
var _committed := false


func _ready() -> void:
	layer = LAYER


## The def ids of the formation, in order: what the world announces a fight with.
func foe_ids() -> Array[StringName]:
	var none: Array[StringName] = []
	return none


## How many of a fight screen's pixels one of a fighter's own pixels covers. The style says how
## many times world size a fighter is drawn at; the division is because a fight screen is a
## CanvasLayer already drawn at the world's scale, so a bare 2.0 under a 2x layer would put a
## 64px cell across 128 of the 180 design pixels a layout is measured for. lpc32 asks for 1 and
## gets world size: the size that character is when you walk around as them.
static func fighter_scale(style: SpriteStyle) -> float:
	return float(style.battle_sprite_scale) / float(UiScale.scale_of(style))
