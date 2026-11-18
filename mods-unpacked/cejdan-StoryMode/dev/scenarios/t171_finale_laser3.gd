extends "res://mods-unpacked/cejdan-StoryMode/dev/scenarios/t171_finale_play.gd"

# Ticket 171: the final battle is tuned for Laser III. The laser bot (see
# t171_finale_play) must win it with that dome, with a fifth of the dome left.


func laser_level() -> int:
	return 3


func expect() -> String:
	return "win"
