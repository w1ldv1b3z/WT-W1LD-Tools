## [v.3.0.0-dev] - 2026-11-05

### Fixed
- Frames / Castbar: A custom cast bar texture now stays in place instead of switching back to the Blizzard texture after casting.
- Frames / UnitFrames: Fixed a Lua error that repeated endlessly on the player frame while resting (especially with taint logging enabled).
- Frames / UnitFrames: The "Hidden" and custom color options for the rest, combat and threat glows now apply reliably and switch back immediately.
- Quest Log: Removed an outdated workaround that interfered with the Blizzard quest log and could cause "Interface action blocked" errors.
- Options: Fixed garbled umlauts in several German option texts (cast bar, unit frames).
- Options: Several settings (accent color, unit frames, cast bar, tooltip border) were only available in German. They are now translated into English as well.
- Chat / History: The error message shown when the chat history cannot be restored is now translated.
- Audio: When you pick your own sound for guild logins, whispers, raid warnings or new Group Finder applicants, the original Blizzard sound is now really muted, so both sounds no longer play on top of each other. This now also works when the Audio module is disabled.
- Audio: WT no longer accidentally mutes unrelated game sounds (e.g. the quest complete sound, drawing weapons or the whisper sound) while a custom guild login sound is active.
- Nameplates: Added missing English texts for the "Square" combo point shape and the test button.
- Keybindings: The chat hotkeys are now really switched off when the Keybindings module is disabled.
- General: More reliable internal event handling. A feature that switches itself off while the game reports an event no longer causes another feature to miss that event, and actions postponed until the end of combat now report errors instead of failing silently.

### Added
- Commands: New `/wt debug` command to switch debug messages in chat on or off. The debug mode had no way to be enabled anymore.

### Changed
- Chat / Smart Logins: Guild members and WoW friends are now handled together by one option ("Smart Guild & Friend Logins"), because the game uses the same login sound for both. The separate "Show Friend Logins" option has been removed. Battle.net friends keep their own option.
- Chat messages: Debug messages, the "Edit Mode" and "WT Update" labels and the on/off status of `/wt gz` are now translated as well.
- Documentation: Removed the non-existent `/wt status` command from the README and the addon description.
- Performance: WT's internal update timer now pauses completely while no feature needs it.
