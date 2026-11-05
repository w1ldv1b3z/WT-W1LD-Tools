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
- Minimap: WT no longer switches off the game's built-in mouse wheel zoom on the minimap. Previously this happened even when all WT minimap options were disabled.
- Minimap: The player arrow is only changed while "Fix Player Arrow" is enabled. Turning the option off restores the Blizzard arrow immediately.
- Action Bars: WT no longer changes your game settings on login. Previously "Key Down Casts", "Auto Push Spells" and the spell queue window were overwritten with WT's values every time you logged in.
- Action Bars: With all options off the action buttons are now left completely untouched. Previously WT changed fonts, text colors, icon colors, the cooldown swipe and the cooldown numbers even when nothing was enabled (e.g. cooldown numbers were shown although they were turned off in the game options).
- Action Bars: Several options (text styling, cooldown hooks) had no effect at all because they targeted a part of the game interface that no longer exists. They work again.
- Action Bars: "Out of Range Tint" works again. With a custom hotkey color, hotkeys now also turn red again while out of range and no longer switch to the custom color when you hover over the button.
- Action Bars: Turning off any action bar option now immediately restores the original look, without a reload. This also applies to Masque support and the vehicle exit button protection.
- Combat Tracker: No longer loads item data, registers events or runs an update timer while neither range nor combat time is enabled.
- Combat Tracker: Fixed a possible Lua error while checking the range items in your bags.
- Combat Tracker: The placeholder shown while moving the display and the range unit names are now translated.
- Time Widget: Left-click (calendar) and right-click (clock settings) now also work when the widget is not movable.
- Time Widget: AM/PM is now shown in your game language.
- Time Widget: Turning the widget off now also stops its internal timer.
- Map Coordinates: Changes to colors and the separator now apply immediately instead of after a reload. Where the game does not provide a position (e.g. in instances), "N/A" is shown instead of "0.0, 0.0".
- General: More reliable internal event handling. A feature that switches itself off while the game reports an event no longer causes another feature to miss that event, and actions postponed until the end of combat now report errors instead of failing silently.

### Added
- Combat Tracker: New option "Highlight Long Boss Fights". During a boss encounter the combat time changes color once it runs longer than the chosen time (e.g. as an enrage timer reminder).
- Combat Tracker: New option "Print Combat Time to Chat". After each fight its duration is printed to the chat; boss fights show the boss name and whether it was a kill or a wipe. Works even with the tracker display hidden.
- Frames / UnitFrames: New option "Combat Glow Only in Real Combat". The game already shows the red combat glow on the player frame as soon as your auto attack starts, even if the target is far out of range; with this option it only appears once you are really in combat.
- Commands: New `/wt debug` command to switch debug messages in chat on or off. The debug mode had no way to be enabled anymore.

### Changed
- General: Module switches are being phased out. Every WT feature stays off until you enable it yourself, and turning a feature off immediately restores the game's default. First step: the "Maps" module switch is gone; the minimap and map coordinate options are now always available.
- Action Bars: The "Action Bars" module switch is gone; its options are always available.
- Action Bars: Removed "Key Down Casts", "Auto Push Spells" and "Hide Blizzard Numbers" because the game's own options (Esc > Options > Gameplay) offer them itself. The spell queue window stays, as the game has no setting for it; the slider now always shows the game's current value.
- Action Bars: "Shorten Hotkeys" now also works without "Custom Hotkey Text".
- Time Widget & Combat Tracker: Their module switches are gone; the options are always available.
- Frames: Removed "Tutorials & HelpTips" and "Allow Talent Alerts". The game has its own option for this (Esc > Options > Gameplay > Interface > Display > "Tutorials"). The WT option could cause "Interface action blocked" errors on the action bars, e.g. when turning in a quest right after a fight. The tutorial setting of the game stays as it is; a hidden setting WT changed for this is reset to the game default.
- Combat Tracker: The range display now uses LibRangeCheck-3.0, the community standard for range estimates. It also uses your own class spells, so it works much better in combat, and it is kept up to date with game changes.
- Combat Tracker: "Hide Out of Combat" now only hides the combat time and is listed under "Show Combat Time". The range display stays visible.
- Time Widget: Removed "Use Server Time" and "24-Hour Format". The widget now follows the game's own clock settings (right-click the widget or the minimap clock), so both clocks always show the same format.
- Minimap: The "Mouse Wheel Zoom" option is hidden on clients where the minimap already zooms with the mouse wheel on its own. "Auto-Reset Zoom" works together with the game's own zoom.
- Chat / Smart Logins: Guild members and WoW friends are now handled together by one option ("Smart Guild & Friend Logins"), because the game uses the same login sound for both. The separate "Show Friend Logins" option has been removed. Battle.net friends keep their own option.
- Chat messages: Debug messages, the "Edit Mode" and "WT Update" labels and the on/off status of `/wt gz` are now translated as well.
- Documentation: Removed the non-existent `/wt status` command from the README and the addon description.
- Performance: WT's internal update timer now pauses completely while no feature needs it.
