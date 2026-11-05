## [v.3.0.0-dev] - 2026-11-05

### Fixed
- Frames / Castbar: A custom cast bar texture now stays in place instead of switching back to the Blizzard texture after casting.
- Frames / UnitFrames: Fixed a Lua error that repeated endlessly on the player frame while resting (especially with taint logging enabled).
- Frames / UnitFrames: The "Hidden" and custom color options for the rest, combat and threat glows now apply reliably and switch back immediately.
- Quest Log: Removed an outdated workaround that interfered with the Blizzard quest log and could cause "Interface action blocked" errors.
- Options: Fixed garbled umlauts in several German option texts (cast bar, unit frames).
- Options: Several settings (accent color, unit frames, cast bar, tooltip border) were only available in German. They are now translated into English as well.
- Chat / History: The error message shown when the chat history cannot be restored is now translated.
- Nameplates: Added missing English texts for the "Square" combo point shape and the test button.

### Added
- Commands: New `/wt debug` command to switch debug messages in chat on or off. The debug mode had no way to be enabled anymore.

### Changed
- Chat messages: Debug messages, the "Edit Mode" and "WT Update" labels and the on/off status of `/wt gz` are now translated as well.
- Documentation: Removed the non-existent `/wt status` command from the README and the addon description.
