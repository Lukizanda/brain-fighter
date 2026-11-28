# SFX tools

Run from the repo root. Needs Python with numpy (scipy is used by the synth code).

1. Render the sounds (director's script, writes `build/sfx/`): `python tools/sfx/render.py`
2. Listening page: `python tools/sfx/audition.py [--dir build/sfx] [--out build/sfx/audition.html]`
   Then double-click `build/sfx/audition.html`. It is one self-contained file you can send to a listener.
   Pick a kit per cue, add notes, press "Copy feedback" and paste the text back. Space stops playback.
3. Check files before upload: `python tools/sfx/lint.py [--dir build/sfx]`
   Exits 1 if any file FAILS (WARN does not fail). From Python: `from lint import lint_file`
   returns a list of `(level, code, message)`.
4. Shortlist variants by measurement: `python tools/sfx/screen.py <family> [--count 800] [--keep 3]`
   Families: `fireball`, `fireball_big`. It first prints its measurements for takes the user
   already judged, then writes `tools/sfx/cues/shortlist_<family>.json`, which the kit turns into cues.
5. Package the chosen sounds for upload: `python tools/sfx/package.py`
   Copies each sound in `tools/sfx/chosen.json` to `build/sfx/upload/<name>.wav`, lints it,
   and writes `build/sfx/upload/UPLOAD.md` (what each file is for, and the upload steps).

How to run a sound session (rules, traps, turning feedback into measurements): `docs/agents/audio-sfx.md`.
