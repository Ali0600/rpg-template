extends Node
## The one place systems announce things to each other.
##
## Signals up, calls down: a view never reaches into another view, and nothing writes
## GameState directly - it emits, and the owner of that state responds. Payload shapes are
## documented on each signal because a Dictionary argument that is only described in the
## emitting file drifts the moment a second emitter appears.

## A generic system finished booting. { "system": StringName }
signal system_ready(info: Dictionary)

## The player entered a map. { "map_id": StringName, "spawn_id": StringName }
signal map_entered(info: Dictionary)

## The player's facing or position changed enough to matter to listeners (footstep audio,
## minimap). { "position": Vector2, "facing": int }  facing is a Dir.D value.
signal player_moved(info: Dictionary)

## An interactable was activated. { "target_id": StringName, "kind": StringName }
signal interacted(info: Dictionary)

## Dialog opened or closed. { "dialog_id": StringName, "open": bool }
signal dialog_changed(info: Dictionary)

## Game flow state changed. { "from": int, "to": int } - Router.State values.
signal flow_changed(info: Dictionary)

## A save slot was written or loaded. { "slot": int, "action": StringName, "ok": bool }
signal save_changed(info: Dictionary)

## Something wants a sound. { "id": StringName, "kind": StringName }
signal sound_requested(info: Dictionary)
