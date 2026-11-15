# Boss score (#172)

The boss sequence's music is written in code: `score.py` (the notes, the cues and their layers) plays instruments from `synth.py` (saw-wavetable strings and brass, a formant choir, taiko and toms, braams, a convolution reverb) and writes seamless loops to `mods-unpacked/cejdan-StoryMode/music/boss_<cue>_<layer>.ogg`. `boss/boss_music.gd` reads those OGGs from their bytes (no import step) and blends the layers with the fight.

| Cue | Tempo, length | Layers |
|---|---|---|
| fight | 132 bpm, 16 bars | 1 the pulse (phase 1), 2 war drums and brass (phase 2), 3 Velle's theme, choir, crashes (phase 3) |
| chase | 160 bpm, 16 bars | 1 the run, 2 what is behind you (louder as the tentacles close in) |
| finale | 140 bpm, 16 bars | 1 battle drums and ostinato, 2 the theme in the horns with choir |

Everything is in D minor. Velle's motif is D-Eb-D-A, in all three cues.

## Regenerate

Needs Python with `numpy`, `scipy`, `soundfile` (and `matplotlib` for `--preview`). From the `Dome Keeper` folder:

```
python art/music/score.py              # all cues
python art/music/score.py chase        # one cue
python art/music/score.py --preview    # also a two-loop full mix and a spectrogram per cue in art/music/preview/
```

The synth is seeded, so the same command gives the same files (rendering one cue alone draws different dice than rendering all three; the committed files come from the plain all-cues run). The master step gives all layers of a cue one shared gain (so their balance holds) aiming at the game's own battle music loudness (about 0.2 RMS for the full mix), and its band balance was matched to the vanilla final-wave music.

Nobody has listened to these with ears yet: the levels, balance and loop seams were checked by measurement and spectrogram only.
