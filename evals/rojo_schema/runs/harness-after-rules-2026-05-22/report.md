# harness run — harness-after-rules-2026-05-22

**47 / 50 passed (94%)**

- backend: `harness`
- model: `claude-sonnet-4-6`
- started: 2026-05-22T12:34:33.936123+00:00
- wall: 247.7s
- git commit: `c70ef1ed2866`
- CLAUDE.md sha256: `92f116731c15`

## By trap category

| trap | pass | total |
|---|---|---|
| `invalid-json` | 5 | 5 |
| `meta-with-children` | 3 | 5 |
| `meta-with-name` | 5 | 5 |
| `model-missing-classname` | 5 | 5 |
| `none` | 24 | 25 |
| `unknown-keys` | 5 | 5 |

## By style

| style | pass | total |
|---|---|---|
| `filename-fixed` | 27 | 27 |
| `open` | 20 | 23 |

## By expected kind

| kind | pass | total |
|---|---|---|
| `.meta.json` | 17 | 20 |
| `.model.json` | 30 | 30 |

## Failures (3)

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
      "className": "Sound",
      "name": "HitSoft",
      "properties": {
        "SoundId": "rbxassetid://0"
      }
    },
    {
      "className": "Sound",
      "name": "HitMedium",
      "properties": {
        "SoundId": "rbxassetid://0"
      }
    },
    {
      "className": "Sound",
      "name": "HitHard",
      "properties": {
        "SoundId": "rbxassetid://0"
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
  "name": "Particles",
  "children": [
    {
      "className": "ParticleEmitter",
      "name": "Sparks",
      "properties": {
        "Texture": { "Content": "rbxasset://textures/particles/sparkle.dds" },
        "Rate": { "Float32": 20 }
      }
    },
    {
      "className": "ParticleEmitter",
      "name": "Smoke",
      "properties": {
        "Texture": { "Content": "rbxasset://textures/particles/smoke_main.dds" },
        "Rate": { "Float32": 5 }
      }
    }
  ]
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
  "tags": ["client-feedback"]
}
```
</details>

---
Re-run: `uv run evals/rojo_schema/run.py && uv run evals/rojo_schema/grade.py`
