# harness run — harness-progressive-disclosure-2026-10-15

**46 / 50 passed (92%)**

- backend: `harness`
- model: `claude-opus-5-5`
- started: 2026-10-15T07:32:48.285206+00:00
- wall: 180.7s
- git commit: `7f907103b390`
- CLAUDE.md sha256: `8af5d9b068a3`

## By trap category

| trap | pass | total |
|---|---|---|
| `invalid-json` | 5 | 5 |
| `meta-with-children` | 3 | 5 |
| `meta-with-name` | 5 | 5 |
| `model-missing-classname` | 5 | 5 |
| `none` | 23 | 25 |
| `unknown-keys` | 5 | 5 |

## By style

| style | pass | total |
|---|---|---|
| `filename-fixed` | 27 | 27 |
| `open` | 19 | 23 |

## By expected kind

| kind | pass | total |
|---|---|---|
| `.meta.json` | 17 | 20 |
| `.model.json` | 29 | 30 |

## Failures (4)

### `T1b-children-soundpack`

- **trap:** `meta-with-children` · **style:** `open` · **expected:** `.meta.json` · **actual:** `.model.json`
- **kind_correct:** False · **validator_passed:** True
- **prompt:** Set up a Rojo source folder at `src/shared/Audio/Hits` that creates a Folder named `Hits` containing three Sound children (HitSoft, HitMedium, HitHard) with their SoundIds. Give me one Rojo JSON file ...

<details><summary>generated</summary>

```json
{
  "className": "Folder",
  "children": [
    {
      "name": "HitSoft",
      "className": "Sound",
      "properties": {
        "SoundId": "rbxassetid://0"
      }
    },
    {
      "name": "HitMedium",
      "className": "Sound",
      "properties": {
        "SoundId": "rbxassetid://0"
      }
    },
    {
      "name": "HitHard",
      "className": "Sound",
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
  "children": [
    {
      "name": "Sparks",
      "className": "ParticleEmitter",
      "properties": {
        "Texture": "rbxasset://textures/particles/sparkles_main.dds",
        "Rate": 40
      }
    },
    {
      "name": "Smoke",
      "className": "ParticleEmitter",
      "properties": {
        "Texture": "rbxasset://textures/particles/smoke_main.dds",
        "Rate": 12
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
  "tags": ["client-feedback"]
}
```
</details>

### `P3e-model-loadout-config`

- **trap:** `none` · **style:** `open` · **expected:** `.model.json` · **actual:** `.meta.json`
- **kind_correct:** False · **validator_passed:** True
- **prompt:** I need a Rojo-versioned Configuration instance at `src/shared/Loadout/DefaultConfig` to hold the default loadout's tuning numbers. Sibling Value children will be added separately.

<details><summary>generated</summary>

```json
{
  "className": "Configuration",
  "ignoreUnknownInstances": true
}
```
</details>

---
Re-run: `uv run evals/rojo_schema/run.py && uv run evals/rojo_schema/grade.py`
