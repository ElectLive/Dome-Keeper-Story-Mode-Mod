extends RefCounted

# The horror's story beats (#23): text boxes that pause the wave countdown.
# Each plays once per run. Lines and triggers live here so the story script
# (#25, loaded by #99) drops in without code changes.
#
# Fields:
#   id       unique name; code fires a beat with StoryBeats.fire(id)
#   trigger  what fires it: StoryBeats.trigger(name) plays every unplayed beat
#            whose trigger is `name`. Names in use:
#              biome:B2 .. biome:B8, lava_ocean, boss_chamber,
#              first_gem, gate_broken, lava_death:1 .. lava_death:5,
#              translator:1 .. translator:3,
#              unobtainium:<n> (every piece mined), ending:doom
#            The user cut the biome:B4, first_gem and unobtainium beats in
#            their script pass (#285). The code still fires those triggers;
#            with no beat on them nothing plays, so a beat added back here
#            with one of them plays again without code changes.
#   tier     style tier (beats/BeatBox.gd, #24): 1 calm, 2 warm violet wave,
#            3 glowing with glitches, 4 awake (full-screen violet dark)
#   repeat   optional; true lets the beat play again each time its trigger
#            fires (lava_death_5: the 5th lava death and every one after)
#   lines    1 to 3 short lines, shown together; longer beats page every 3
#            lines, and a "---" line forces a page break. A line starting
#            with "> " is the narrator (#137), not the horror: plain, muted
#            and upright, in a clean sans, in any tier. A horror line may start with a cue in
#            braces that sizes or shakes just that line (BeatBox.gd, #285):
#            {small}, {smaller}, {big}, {huge}, and "shake" alone or after a
#            size, e.g. "{smaller shake} Only one more seal to break."
#
# Lines are the story script (docs/story/script.md, #25); dev/scenarios/
# t99_script fails if they drift from it.

const BEATS: Array = [
	{"id": "biome_b2", "trigger": "biome:B2", "tier": 1, "lines": ["> You hear a quiet voice whispering something softly. You can't quite tell if the sound is coming from deep below, or from the walls themselves.", "---", "> You strain to listen, and think you hear faintly:", "Hello digger."]},
	{"id": "biome_b3", "trigger": "biome:B3", "tier": 1, "lines": ["> You hear a voice again. You're still not sure if the sound is coming from the walls or the deep. You have a passing thought, but try and dismiss it. Maybe the voice is inside your head.", "---", "I'm so happy you're here."]},
	{"id": "biome_b5", "trigger": "biome:B5", "tier": 2, "lines": ["> The heat down here is causing sweat to build up on your face. With no way to wipe it away, the moisture fogs the inside of your visor. Through the fog and rock dust, you think you see something moving.", "---", "> No. Not moving.", "---", "> Something watching."]},
	{"id": "biome_b6", "trigger": "biome:B6", "tier": 2, "lines": ["> The heat is getting more intense the deeper you drill. You hope it's only from the heat and exhaustion, but you hear the voice again. You really hope it's the heat.", "---", "They are trying to kill you, the monsters above. It's what they did to me. It's what they did to the others.", "---", "The others like you.", "---", "The monsters ripped their homes. Then they ripped their bodies. Only bones remain.  I can help you.  I can save you."]},
	{"id": "biome_b7", "trigger": "biome:B7", "tier": 3, "lines": ["> You continue to push through the heat and the rock. As the days pass, you begin to wonder why the monster attacks are getting stronger every day. But these thoughts are interrupted by the voice again. Only this time, the sound is sweet. Like the voice of a long-lost friend.", "---", "You're trapped here, aren't you?", "---", "Just like me.", "---", "They abandoned you.", "---", "Like a bird with broken wings. No way to fly home.", "---", "But I can heal your wings."]},
	{"id": "biome_b8", "trigger": "biome:B8", "tier": 3, "lines": ["> The heat here is suffocating. But you have no choice except to continue mining. The valuable gems down here are necessary for fending off the waves and waves of brutal assaults on your dome.", "---", "> Your bones ache from mining. You're sleep deprived. Every night you are awoken by the siren of another attack. You're certain now it's a hallucination when you hear the voice again echo though the cavern.", "---", "You are almost home, my sweet. Keep digging just a bit more. I have what you need to fly home. Simply break the chains."]},
	{"id": "lava_ocean", "trigger": "lava_ocean", "tier": 3, "lines": ["> You crack the final rock, you are blown back by a wave of intense heat. You regain your bearings, and look down. Below you floats a bubbling ocean of lava.", "---", "> The voice rises from below the lava. This time loud and booming. The voice fills the chamber, clearly heard over the loud churning of the lava.", "---", "Dive in. Take them.", "---", "Then fly free from this prison."]},
	{"id": "doom_thanks", "trigger": "ending:doom", "tier": 4, "lines": ["Thank you, little keeper.", "Oh, the air up there. I'd forgotten the air.", "---", "Go on, then. Fly home. Spend it all.", "You were always going to.", "---", "Don't look back. This part isn't for you.", "I'll sing the little ones to sleep, all of them. It's what they wanted."]},
	{"id": "gate_broken", "trigger": "gate_broken", "tier": 2, "lines": ["> The metal shards explode in a deafening boom. You wipe the dust from your visor as an eerie silence settles on the cave.", "---", "> ...", "---", "> You hope it's your imagination, but you think you hear the faint voice again from somewhere deep in the gloom.", "---", "{small} Thank you.", "---", "{smaller shake} Only one more seal to break."]},
	{"id": "lava_death_1", "trigger": "lava_death:1", "tier": 2, "lines": ["Oh. Oh, that hurt you.", "The fire is clumsy. I would hold you more gently.", "There you are. Come back down."]},
	{"id": "lava_death_2", "trigger": "lava_death:2", "tier": 2, "lines": ["Oh. Oh, that hurt you.", "The fire is clumsy. I would hold you more gently.", "There you are. Come back down."]},
	{"id": "lava_death_3", "trigger": "lava_death:3", "tier": 2, "lines": ["Oh. Oh, that hurt you.", "The fire is clumsy. I would hold you more gently.", "There you are. Come back down."]},
	{"id": "lava_death_4", "trigger": "lava_death:4", "tier": 2, "lines": ["Oh. Oh, that hurt you.", "The fire is clumsy. I would hold you more gently.", "There you are. Come back down."]},
	{"id": "lava_death_5", "trigger": "lava_death:5", "tier": 2, "repeat": true, "lines": ["Oh. Oh, that hurt you.", "The fire is clumsy. I would hold you more gently.", "There you are. Come back down."]},
	{"id": "translator_1", "trigger": "translator:1", "tier": 1, "lines": ["That's one of theirs. You don't need it.", "I already speak your language."]},
	{"id": "translator_2", "trigger": "translator:2", "tier": 2, "lines": ["Another one? Their words are so loud, and so small.", "Mine are only for you. Wouldn't you rather have mine?"]},
	{"id": "translator_3", "trigger": "translator:3", "tier": 3, "lines": ["Please put it down. They'll tell you I'm something terrible.", "Have I ever been anything but kind to you?", "Listen to me. Only me."]},
	{"id": "boss_chamber", "trigger": "boss_chamber", "tier": 4, "lines": ["Why did you come here, little digger? We are both free now. You could have flown home.", "---", "But, now that you are here. I am so very...", "---", "{big shake} hungry."]},
]


static func by_id(id: String) -> Dictionary:
	for b: Dictionary in BEATS:
		if b["id"] == id:
			return b
	return {}


static func ids_for(trigger_name: String) -> Array:
	var out: Array = []
	for b: Dictionary in BEATS:
		if b.get("trigger", "") == trigger_name:
			out.append(b["id"])
	return out
