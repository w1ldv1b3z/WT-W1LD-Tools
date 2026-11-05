================================================================================
                              W1LD Tools (WT)
================================================================================

W1LD Tools (WT) is a modular UI and system tweak collection for 
World of Warcraft Retail & WoW Forever (Camelot - BETA).

Originally, I wrote this addon primarily for myself. Over time, an incredible 
number of small tools, quality-of-life adjustments, and tweaks have accumulated 
that make my everyday life in the game easier. Instead of using countless 
individual addons for this, I wanted to combine everything in one place, make 
it configurable, and store it in a structured way.

The result is WT. The addon is divided into modular systems, all of which can 
be toggled on or off individually. So you only load the things you really need. 
It integrates directly into the WoW options menu, automatically detects your 
client version (Retail or WoW Forever), and comes with its own search function 
for the settings.

--------------------------------------------------------------------------------
INSTALLATION
--------------------------------------------------------------------------------
1. Download the latest release from CurseForge.
2. Extract the "WT" folder into your World of Warcraft 
   "_retail_\Interface\AddOns\" (or WoW Forever "Interface\AddOns\")
   directory.
3. Start the game and type /wt in chat to open the configuration menu.

--------------------------------------------------------------------------------
FEATURE OVERVIEW
--------------------------------------------------------------------------------
MULTI-CLIENT COMPATIBILITY (RETAIL & WOW FOREVER - BETA)
NOTE: Support for WoW Forever (1.60.x / Camelot) is currently in BETA. 
While core systems have been adapted, testing is actively ongoing!
- Dual Compatibility: Full native support for WoW Retail (Midnight 12.1.x / TWW)
  and preliminary support for WoW Forever (1.60.x / Camelot - Beta).
- Intelligent Flavor Detection: Automatically detects your game version at
  runtime. The options panel header displays your active environment and
  dynamically tags or disables incompatible settings ([Retail Only] / [Forever Only]).
- Client-Specific Adaptations: On WoW Forever, includes Slot 18 (Ranged / Wand / Relic)
  item levels and durability, legacy enchants (Gloves, Ranged, Head, Shoulders),
  routing database links to wowhead.com/forever/ & ForeverDB, and filtering non-vanilla classes.

ACCOUNT-WIDE SETTINGS SYNC
- Master Profile System: Fully replaces external addons like "Account Wide 
  Interface Settings". WT dynamically captures 100% of your non-hardware 
  WoW settings (Keybindings, Macros, and all Interface CVars) on your main 
  character and automatically mirrors them to all your alts on login! 
  Includes an intelligent auto-save function and a smart Blacklist to prevent 
  syncing hardware-specific settings across different PCs.
- Chat Sync: Ensures your chat channels, message groups, and settings are 
  perfectly synced across your entire account. (Note: physical tab layouts are 
  excluded to prevent Edit Mode conflicts; see in-game UI for a manual copy tip).

WINDOWS & UI
- Scrollable Dropdown Menus: All dropdowns in the settings panel with larger 
  option lists (SharedMedia sounds, fonts, textures) feature smooth mouse wheel 
  scrolling, a custom slim scrollbar, auto-scrolling to the active selection, 
  and smart screen clamping (flips upward when close to screen bottom).
- Extended ColorPicker: Replaces the default WoW color picker, enabling you to 
  save custom colors and quickly access class colors.
- Move Windows: Move and scale most standard WoW windows with a modifier key.
- Alerts & Toasts: Reposition loot, achievements, BNet toasts, and errors.
- Hide Elements: Hide XP bars, the bag bar or the Talking Head.
- Class-specific Colors: Replaces standard class colors in various UI elements.
- Camera & Visuals: Increases max camera zoom, disables low health screen glow.
- Combat Cursor: Highlights the cursor with colors or click animations.

ACTION BARS
- Key Down Casts: Trigger spells directly upon pressing the key down.
- Spell Queue Window: Adjust your spell queue window directly to match your ping 
  for zero input lag.
- Clean Text: Shorten or hide macro and hotkey texts.
- Cooldowns: Color-adjust or hide default cooldown numbers.

CHARACTER & INSPECT
- Item Level & Enchants: Shows item levels, socketed gems, and enchantments on 
  equipment slots and in the inspect window. Supports Slot 18 and legacy 
  enchants on WoW Forever.
- Durability: Displays a durability percentage on your items.

HUD FADER & NAMEPLATES
- Fader: Hides action bars, bags, or menus when out of combat/not hovering.
- Automatic Nameplates: Automatically turns on enemy nameplates in combat.
- Colors & Highlights: Class colors in PvP, highlights casters/bosses, threat.
- Quest Indicator: Shows if an enemy is important for your current quest.
- Class-Specific Resources: Displays class-specific resources (e.g. combo points) 
  on your target's nameplate with various shapes, sizes, and coloring options.

LOOT, INVENTORY & VENDORS
- Fast Looting: Instantly loots everything by completely bypassing the loot window.
- Loot Under Mouse: Opens the loot window directly at your cursor.
- Easy Delete / Destroy: Automatically fills in "DELETE" (or "DESTROY" for custom 
  housing objects) in confirmation dialogs.
- Sell Junk: Sells grey junk with one click (protecting equipment sets). Use 
  CTRL+ALT+Click to exclude specific items. Identifies junk in your bags 
  visually (supports Bagnon & Baganator).
- Auto-Repair: Automatically repairs at the vendor.

AUTOMATION & QUALITY OF LIFE
- Rogue Poison Reminder: A dedicated HUD for Rogues reminding you to apply and 
  maintain your poisons. Full dual compatibility: monitors Lethal & Non-Lethal 
  player auras on Retail, and Main-Hand & Off-Hand temporary weapon enchants on 
  WoW Forever. Features live duration countdowns, differentiated visual states 
  (amber pulse when expiring soon, red pulse when missing), customizable frame 
  scaling (0.5x - 2.0x), an interactive edit mode with live coordinates (X | Y), 
  nudge arrow buttons, and quick reset (Right-Click: Close, Middle-Click: Reset), 
  standard ALT+Drag repositioning (defaults to screen center), audio alerts with 
  channel routing and preview, chat warnings, combat start reminders (strictly 
  for missing poisons), and smart context suppression (dead, taxi, vehicle, etc.).
- Mythic+ Keystones: Automatically places your keystone in the slot.
- Combat Resurrection: Automatically accepts battle rezzes in PvE.
- Auto-Dismount/Stand: Dismounts and stands you up when you start casting.
- Automatic Reputation: Switches tracked rep to the faction you gained rep with.
- Fishing Enhancements: Modifier+double-click casting, Smart Audio, and a dynamic 
  1-button cast/interact keybind.
- Farming (Sunsong Ranch): Creates a handy bar with tools and seeds.

AUDIO & SOUNDS
- Sound Routing & Preview: Routes sounds through audio channels of your choice 
  (Master, Dialog, SFX, Music, Ambience) with instant live preview buttons and 
  fallback sound IDs for WoW Forever.
- Sound Blacklist: Specifically mute certain standard game sounds.

QUESTING & DIALOGS
- Auto-Questing: Automatically accept and turn in quests.
- Smart Gossip: Skips useless NPC dialogs if there is only one option.
- Cinematics: Can automatically skip in-game cutscenes and videos.

MAP & MINIMAP
- Minimap Zoom: Allows zooming the minimap via the mouse wheel.
- Map Transparency: Makes the large world map transparent while moving.
- Coordinates: Shows player and cursor position on the world map.

GROUPS & LFG
- Auto-Accept: Automatically accept invites from friends, role checks, summons.
- LFG Enhancements: Shows faction icons and country flags in the group finder.

CHAT & COMMUNICATION
- Chat Copy: Easily extract and copy full chat histories from a dedicated window.
- Visual Adjustments: Class colors, hide server names, show player levels.
- Better Usability: Clickable links, mouse wheel scrolling, arrow key nav.
- Chat History: Saves chat history across game sessions (supports global and 
  custom channels. Note: Battle.net Whispers and Community chats cannot be saved 
  due to Blizzard restrictions).
- Word Filters & Highlights: Block words or highlight terms with color/sound.
- Channel Customization: Custom aliases or colors for chat channels.

TOOLTIPS
- Player Info: Adds Item Level, M+ Rating, PvP Rating to the tooltip.
- Items: Shows expansion, known recipes/toys, bank materials.
- Database Links: ALT-click to generate Wowhead or Raider.io links (automatically 
  routes to wowhead.com/forever/ & ForeverDB on WoW Forever).
- NerdIDs: Shows internal IDs of spells, items, and NPCs.
- Anchor to Cursor: Appears directly at the mouse instead of bottom right.

SMALL TRACKERS / WIDGETS
- System: Displays FPS, latency, and memory usage.
- Time: A small widget for time and date.
- Social: Shows online guild members and Battle.net friends.

--------------------------------------------------------------------------------
CUSTOM MEDIA
--------------------------------------------------------------------------------
You can register and inject your own custom fonts, sounds, status bars,
backgrounds, borders, and highlight textures into the addon. 
Simply open the file "Utils/CustomMedia.lua"
and follow the instructions inside.

--------------------------------------------------------------------------------
SLASH COMMANDS
--------------------------------------------------------------------------------
Type /wt help in-game for a full list of available commands. Important ones:
- /wt                 : Opens the configuration menu.
- /wt reset pos       : Resets manually modified window positions.
- /wt reset scale     : Resets manually modified window scales.
- /wt reset config    : Resets both positions and scales.
- /wt reset poison    : Resets Rogue Poison Reminder to screen center.
- /wt debug           : Toggles debug messages in chat (useful for bug reports).

--------------------------------------------------------------------------------
SUPPORTED LANGUAGES
--------------------------------------------------------------------------------
- English (enUS)
- German  (deDE)

Have fun with W1LD Tools!