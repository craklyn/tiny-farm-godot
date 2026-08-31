# player_brain.gd — The farmer's row in the brain table (M2.5 WI-3)
#
# Layer 2 (pure), and deliberately empty. **The player is a person, not a
# policy.** Her actions come from her taps, through `systems/input_manager.gd`
# and `systems/action_router.gd` — layers 4 and 3, where the architecture puts
# "gesture or bot-policy → Action". Nothing in the sim may decide for her.
#
# It exists so the registry has no special case for her: every species row names
# a brain, `Brains.of_actor()` answers for everybody, and the day a bot line
# lands (WI-9) the difference between the farmer and a follow-bot is one string
# in a table rather than a branch in the dispatcher. That is P-9's "bots get no
# verb the player lacks" written from the other side — she gets no *machinery*
# they lack either.
#
# Off the clock, obviously: sim time must never step the player.
class_name PlayerBrain
extends Brain


func on_clock() -> bool:
	return false
