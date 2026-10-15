# Project structure

The spelling-combat chain:

LetterBlock → BlockShoot → WordBuffer → Dictionary / EnergyEconomy → EnergyReservoirs → MemorizeAction → SpellRegistry → CastAction → SpellExecutor → Skills → Vfx

It sits alongside the surviving template systems: Health, NPC, GameMode, Boss and Dash. The TPS weapon/loadout/locomotion stack, the LetterBlaster Tool and BossAdapter have all been deleted. Their wiki pages are historical records only.

This tree is representative, not complete. `src/` is the authority.
```
src/
  client/          LocalScripts: BlockTapController, DashManager, DevDebug, SettingsController,
                   SpellCastController/, PlayerSession (module)
    UI/            one coordinator LocalScript per HUD element
    Vfx/           VfxController (caster prediction), WorldVfxController (the one broadcast lane),
                   status controllers (Shield/Freeze/Inferno/ChargeOrb/BarrierCrumble)
  server/          Health, GameMode (GameModeService/RoundManager/SessionRegistry), Boss, NPC + AI,
                   BlockShoot, BlockSpawner, SpellCast(+Service), Economy (EnergyLedger), Lobby,
                   Analytics, Arena, Dev, Tests (TestAutoRunner)
  shared/
    Core/          Logger, Colors, InputCategorizer, GameConfig
    Character/     DashController
    Health/        damage types, constants, modifiers, getHitZone, Remotes/
    Hud/           Builder + Config pair per element, HudConstants, HudLayoutManager, HudGate
    GameMode/      Modes/ (PvEBoss, PvPDuel, Lobby, NoOp), Arena, Remotes/
    NPC/ Boss/ Lobby/ Settings/ Economy/ SpellCast/
    Dictionary/ WordBuffer/ EnergyEconomy/ EnergyReservoirs/ Wildcard/
    SpellRegistry/ SpellExecutor/ CastAction/ MemorizeAction/ MindFullManager/
    Skills/        SkillTypes/Effects/Delivery/Interrupt/Visuals/Buffs
    Vfx/           VfxConfig, spawnEffect, VfxBroadcast, CosmeticProjectile, StatusVisuals/
    BlockShoot/ BlockSpawner/ LetterBlocks/
    Weapon/        no code; ignoreUnknownInstances shell for Studio-side Objects (LaserBeam)
    Tests/         TestRunner + Suites/
  StarterCharacterScripts/   Health.client.luau
  utility/         lerp
```
