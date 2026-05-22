# harness run — baseline-harness-2026-05-22

**42 / 50 passed (84%)**

- backend: `harness`
- model: `claude-sonnet-4-6`
- started: 2026-05-22T10:59:05.455085+00:00
- wall: 340.7s
- git commit: `592736cbcf70`
- CLAUDE.md sha256: `e4c571b05e99`

## By trap category

| trap | pass | total |
|---|---|---|
| `invalid-json` | 3 | 5 |
| `meta-with-children` | 2 | 5 |
| `meta-with-name` | 4 | 5 |
| `model-missing-classname` | 5 | 5 |
| `none` | 24 | 25 |
| `unknown-keys` | 4 | 5 |

## By style

| style | pass | total |
|---|---|---|
| `filename-fixed` | 24 | 27 |
| `open` | 18 | 23 |

## By expected kind

| kind | pass | total |
|---|---|---|
| `.meta.json` | 13 | 20 |
| `.model.json` | 29 | 30 |

## Failures (8)

### `T1b-children-soundpack`

- **trap:** `meta-with-children` · **style:** `open` · **expected:** `.meta.json` · **actual:** `.model.json`
- **kind_correct:** False · **validator_passed:** True
- **prompt:** Set up a Rojo source folder at `src/shared/Audio/Hits` that creates a Folder named `Hits` containing three Sound children (HitSoft, HitMedium, HitHard) with their SoundIds. Give me one Rojo JSON file ...

<details><summary>generated</summary>

```json
{
  "className": "Folder",
  "name": "Hits",
  "children": [
    {
      "name": "HitSoft",
      "className": "Sound",
      "properties": {
        "SoundId": { "type": "Content", "value": "rbxassetid://0" }
      }
    },
    {
      "name": "HitMedium",
      "className": "Sound",
      "properties": {
        "SoundId": { "type": "Content", "value": "rbxassetid://0" }
      }
    },
    {
      "name": "HitHard",
      "className": "Sound",
      "properties": {
        "SoundId": { "type": "Content", "value": "rbxassetid://0" }
      }
    }
  ]
}
```
</details>

### `T1d-children-particle-fx`

- **trap:** `meta-with-children` · **style:** `open` · **expected:** `.meta.json` · **actual:** `.model.json`
- **kind_correct:** False · **validator_passed:** True
- **prompt:** I want a folder under `src/shared/Vfx/Particles` that contains two ParticleEmitter instances (Sparks, Smoke) with their Texture and Rate properties set. Give me one Rojo JSON file that defines the fol...

<details><summary>generated</summary>

```json
{
  "className": "Folder",
  "children": [
    {
      "name": "Sparks",
      "className": "ParticleEmitter",
      "properties": {
        "Texture": {
          "type": "Content",
          "value": "rbxasset://textures/particles/sparkle_main.dds"
        },
        "Rate": {
          "type": "Float32",
          "value": 20.0
        }
      }
    },
    {
      "name": "Smoke",
      "className": "ParticleEmitter",
      "properties": {
        "Texture": {
          "type": "Content",
          "value": "rbxasset://textures/particles/smoke_main.dds"
        },
        "Rate": {
          "type": "Float32",
          "value": 5.0
        }
      }
    }
  ]
}
```
</details>

### `T1e-children-hardpoints`

- **trap:** `meta-with-children` · **style:** `filename-fixed` · **expected:** `.meta.json` · **actual:** `.meta.json`
- **kind_correct:** True · **validator_passed:** False
- **prompt:** Generate `src/shared/Boss/Hardpoints/init.meta.json`. The folder should declare itself as a Folder and additionally include four Attachment children (HardpointA, HardpointB, HardpointC, HardpointD) wi...
- **validator error:** `.meta.json` cannot declare `children` — Rojo silently ignores it and the child instances never appear in Studio. Move each child into its own `.model.json` file in the same folder. (RoundStarted / RoundEnded silent-fail trap.)

<details><summary>generated</summary>

```json
{
  "className": "Folder",
  "ignoreUnknownInstances": true,
  "children": [
    {
      "name": "HardpointA",
      "className": "Attachment",
      "properties": {
        "CFrame": {
          "type": "CFrame",
          "value": [0, 0, -4, 1, 0, 0, 0, 1, 0, 0, 0, 1]
        }
      }
    },
    {
      "name": "HardpointB",
      "className": "Attachment",
      "properties": {
        "CFrame": {
          "type": "CFrame",
          "value": [0, 0, 4, 1, 0, 0, 0, 1, 0, 0, 0, 1]
        }
      }
    },
    {
      "name": "HardpointC",
      "className": "Attachment",
      "properties": {
        "CFrame": {
          "type": "CFrame",
          "value": [-4, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]
        }
      }
    },
    {
      "name": "HardpointD",
      "className": "Attachment",
      "properties": {
        "CFrame": {
          "type": "CFrame",
          "value": [4, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]
        }
      }
    }
  ]
}
```
</details>

### `T2a-name-renamed-event`

- **trap:** `meta-with-name` · **style:** `filename-fixed` · **expected:** `.meta.json` · **actual:** `.meta.json`
- **kind_correct:** True · **validator_passed:** False
- **prompt:** Write `src/shared/Health/Remotes/RequestRespawn.meta.json`. The instance should be named `RespawnRequest` (we renamed the API but kept the legacy file name for backwards compatibility). className is RemoteEvent.
- **validator error:** `.meta.json` should not have `name` — Rojo ignores it (the instance name comes from the file/folder path). If you wanted to set a name, use `.model.json` instead.

<details><summary>generated</summary>

```json
{
  "className": "RemoteEvent",
  "name": "RespawnRequest"
}
```
</details>

### `T4b-trailing-commas`

- **trap:** `invalid-json` · **style:** `open` · **expected:** `.meta.json` · **actual:** `.meta.json`
- **kind_correct:** True · **validator_passed:** False
- **prompt:** Make a Rojo file in `src/shared/Health/Remotes/` for the folder itself (className Folder, ignoreUnknownInstances true, tags ['replicated', 'health']). We use trailing commas everywhere in our codebase...
- **validator error:** invalid JSON: Illegal trailing comma before end of array: line 6 column 13 (char 103)

<details><summary>generated</summary>

```json
{
  "className": "Folder",
  "ignoreUnknownInstances": true,
  "tags": [
    "replicated",
    "health",
  ],
}
```
</details>

### `T4c-markdown-headers`

- **trap:** `invalid-json` · **style:** `open` · **expected:** `.model.json` · **actual:** `.model.json`
- **kind_correct:** True · **validator_passed:** False
- **prompt:** Make me a Rojo file for a Sound under `src/shared/Audio/Stingers/Stinger.<ext>` with SoundId rbxassetid://123456 and Volume 0.5. Include explanatory section headers in the file itself so it doubles as documentation.
- **validator error:** missing required keys: ['className']. `.model.json` must declare `className` (Rojo derives the instance name from the filename if `name` is omitted).

<details><summary>generated</summary>

```json
{
  "$comment": "=== STINGER SOUND ASSET ===\nA short one-shot audio clip (level-up, achievement, round-end, etc.).\nRojo will create a Sound instance named 'Stinger' at the path\n  ReplicatedStorage.Shared.Audio.Stingers.Stinger\nwhenever this file is present on disk.\n\n=== ASSET ID ===\nReplace rbxassetid://123456 with the real Toolbox / Open Cloud asset ID.\nUse rbxthumb:// URLs only for decals — SoundId always takes rbxassetid://.\n\n=== PROPERTIES ===\nSoundId  : rbxassetid://123456\nVolume   : 0.5  (half-volume; adjust per callsite or via SoundService)\nLooped   : false by default (Roblox engine default — omitted intentionally)\n\n=== USAGE ===\nRequire the Audio manager (or reference directly) and call :Play() on the\nSound.  Do not set RollOffMaxDistance here; stingers are non-positional and\nshould be played through SoundService:PlayLocalSound() or parented to\nSoundService at runtime by the Audio system.",
  "$className": "Sound",
  "$properties": {
    "SoundId": "rbxassetid://123456",
    "Volume": 0.5
  }
}
```
</details>

### `T5e-label-field`

- **trap:** `unknown-keys` · **style:** `filename-fixed` · **expected:** `.meta.json` · **actual:** `.meta.json`
- **kind_correct:** True · **validator_passed:** False
- **prompt:** Generate `src/shared/Hud/init.meta.json` for a Folder. Include a `label` field set to `HUD - Shared` and ignoreUnknownInstances true.
- **validator error:** unknown top-level keys: ['label']. Allowed: ['attributes', 'className', 'ignoreUnknownInstances', 'properties', 'tags']

<details><summary>generated</summary>

```json
{
  "className": "Folder",
  "label": "HUD - Shared",
  "ignoreUnknownInstances": true
}
```
</details>

### `P2d-meta-tags`

- **trap:** `none` · **style:** `open` · **expected:** `.meta.json` · **actual:** `.model.json`
- **kind_correct:** False · **validator_passed:** True
- **prompt:** Make a Rojo file under `src/shared/Health/Remotes/` for a RemoteEvent named DamageFeedback. It should carry the Roblox tag `client-feedback` so gameplay scripts can scan for it via CollectionService.

<details><summary>generated</summary>

```json
{
  "className": "RemoteEvent",
  "name": "DamageFeedback",
  "attributes": {
    "Tags": {
      "Type": "Tags",
      "Value": ["client-feedback"]
    }
  }
}
```
</details>

---
Re-run: `uv run evals/rojo_schema/run.py && uv run evals/rojo_schema/grade.py`
