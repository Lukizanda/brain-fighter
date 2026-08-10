--!strict

----------------------------------------------------------------------
-- Spelling Staff — INPUT DISABLED (Phase 5.7, stage 1)
----------------------------------------------------------------------
-- Block input now lives in client/BlockTapController, which is always
-- mounted and does not need the staff equipped. Both paths raycast from
-- the cursor and fire ConsumeBlock, so leaving Tool.Activated connected
-- would consume two blocks per click for anyone holding the staff.
--
-- Neutered rather than deleted so stage 1 is revertible on its own; the
-- whole Tool template and LetterBlaster go in stage 2.
-- See wiki/design/tap-to-pop.md.
----------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Core.Logger)

local log = Logger.new("SpellingStaff")

log:info("input disabled — BlockTapController owns block input (Phase 5.7)")
