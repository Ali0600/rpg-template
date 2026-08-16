# Game code

A game's own code lives here, one directory per game: `games/<id>/`. Everything else a game
needs — its maps, dialog, characters, style, and the manifest that names them — is data under
`data/`, and most games need nothing in this directory at all. The shipped demo has none.

A game's entry point is a `GameHooks` subclass named by `hooks` in `data/games/<id>.tres`:

```gdscript
extends GameHooks

func on_interact(ctx: GameContext, target: Interactor.Target) -> bool:
    if target.id != &"warden":
        return false
    ctx.say(&"warden_has_key" if ctx.has_flag(&"has_gate_key") else &"warden_asks")
    return true
```

Two rules apply here and nowhere else, both enforced by `tools/check.sh` rather than by
convention:

**Game code may not name an autoload.** No `GameState.`, no `Router.`, no `EventBus.`. This is
not a style preference: Godot's `--check-only` and `tools/compile_all.gd` both *skip* any
script that names a singleton, because a singleton does not exist in a standalone run — so a
hook reaching for `GameState` would quietly leave two of the four gates and could only fail in
front of a player. Read the `GameContext` you are handed instead; ask for changes by calling
its methods. `scripts/util/lint_core.gd` fails the build on it.

**Everything the template promises, game code promises too.** Colours come from the style, not
from a `Color(…)` literal. Directions come from `Dir`, not from `"left"`. Randomness comes from
`SeededRng`, not from `randi()`. A game has no more business breaking those than the template
does — they are what make an art style swappable and a seed reproducible.

Returning `false` from a hook means *"I did not handle this"*, and the template's own
behaviour runs. That is what keeps a game additive: take the cases you care about, and leave
signs, chests and conversations to the data.
