# EzSwitch

<p align="center">
  <img src="icon.png" alt="EzSwitch Icon" width="128" height="128">
</p>

<p align="center">
  <strong>A macOS menu bar utility for keyboard layout switching and text transformation</strong>
</p>

<p align="center">
  Inspired by Caramba Switcher and Karabiner-Elements
</p>

<p align="center">
  <img src="screenshots/ezSwitch-app.png" alt="EzSwitch Settings" width="380">
</p>

## Features

### Command Key Layout Switching
- Press **left Command** key → switch to left layout (configurable)
- Press **right Command** key → switch to right layout (configurable)
- Works as a quick tap (not holding)
- **Works with any pair of languages**, not just Russian and English
- The modifier family (Command or Option) is selectable from the **Key** dropdown

### Text Transformation
- Double-tap **Shift** (or **Option**) to transform selected text between keyboard layouts
- Works with selected text or the last word before cursor
- Supports various key combinations:
  - Double left/right Shift
  - Double left/right Option
  - Double any Shift/Option
- **Suppress in apps** toggle — blocks the double-tap from reaching apps where it triggers something unwanted (e.g. PHPStorm's Search Everywhere on double Shift)
- **Switch layout after** — automatically follow the transformed text to its target layout
- **Supports any pair of layouts** via the **Mappers** settings (see below)

### Smart App Detection (work in progress)
- Automatically detects the current application
- Uses appropriate word selection method (Option+Shift+Left for macOS apps, Ctrl+Shift+Left for IDEs)
- Supports JetBrains IDEs, VS Code, browsers, and more

### Customizable Keyboard Mappers
- Configure character mappings for **any pair of keyboard layouts** — no hand-written mapper file needed
- **Auto-generated** mappings via macOS `UCKeyTranslate` API: select two layouts and a complete mapping is built instantly from the actual key code tables
- Visual QWERTY editor — click any key to override or fine-tune
- **Multi-character targets** — a single source key can map to a sequence (e.g. `й → "ja"`, `ц → "tz"`, emoji, abbreviations). Multi-char values are preserved on disk and sanitization skips them on load
- **Reverse direction is automatic** — store only one preset per language pair; the opposite direction is rebuilt via longest-match so values like `й → "ja"` reverse back to `я` correctly
- **Active preset is per pair** — pick which preset is used for each language pair from the popover; selection persists across restarts
- Save mappings as **presets** and reuse them across restarts
- **Auto-seeded on first launch** — an `UCKeyTranslate`-generated preset is created for the user's current left/right language pair so the app works out of the box for any installed layout
- Presets are stored in `~/Library/Application Support/EzSwitch/presets.json`
  - **Word-level substitutions** — teach the app individual words that always need the other layout (e.g. `пше → git`); on word boundary (space/Enter/punctuation) they're auto-replaced and case is preserved
  - **Configurable remember hotkey** (default ⌘⇧M) — type the word and press the hotkey; the word is replaced in place with its equivalent in the other layout **and** the pair is stored in the dictionary. Works on a buffered word (no separator typed) or on a selected word — the keyboard layout is **not** changed
  - **Layout stays put** — both auto-replace and hotkey training deliver the replacement through the system clipboard, so you keep typing in whichever layout you were in
  - **Per-pair, one-way entries** — each pair direction has its own list; add the reverse manually if you want bidirectional
  - Word mappings are stored in `~/Library/Application Support/EzSwitch/word_mappings.json`
  - **Delete is guarded by a confirmation dialog** — no accidental loss of long-curated mappings

#### Mapper Editor — Visual Keyboard Layout
The editor shows a 48-key QWERTY grid (4 rows × 14/13/11/10 keys). Each key displays its current base + Shift mapping.

| Row | Position | Key (ID) | Virtual Key Code (hex) | Notes |
|-----|----------|----------|------------------------|-------|
| 1 | 1 | backtick | `0x32` | EN: `` ` `` `~` / RU: `ё` `Ё` |
| 1 | 2 | section  | `0x0A` | EN: `§` `±` / RU: `ё` `Ё` |
| 1 | 3 | 1 | `0x12` | EN: `1` `!` / RU: `1` `!` |
| 1 | 4 | 2 | `0x13` | EN: `2` `@` / RU: `2` `"` |
| 1 | 5 | 3 | `0x14` | EN: `3` `#` / RU: `3` `№` |
| 1 | 6 | 4 | `0x15` | EN: `4` `$` / RU: `4` `;` |
| 1 | 7 | 5 | `0x16` | EN: `5` `%` / RU: `5` `%` |
| 1 | 8 | 6 | `0x17` | EN: `6` `^` / RU: `6` `:` |
| 1 | 9 | 7 | `0x1C` | EN: `7` `&` / RU: `7` `?` |
| 1 | 10 | 8 | `0x19` | EN: `8` `*` / RU: `8` `*` |
| 1 | 11 | 9 | `0x1A` | EN: `9` `(` / RU: `9` `(` |
| 1 | 12 | 0 | `0x1D` | EN: `0` `)` / RU: `0` `)` |
| 1 | 13 | minus | `0x1B` | EN: `-` `_` / RU: `-` `_` |
| 1 | 14 | equal | `0x18` | EN: `=` `+` / RU: `=` `+` |
| 2 | 1 | q | `0x0C` | |
| 2 | 2 | w | `0x0D` | |
| 2 | 3 | e | `0x0E` | |
| 2 | 4 | r | `0x0F` | |
| 2 | 5 | t | `0x11` | |
| 2 | 6 | y | `0x10` | |
| 2 | 7 | u | `0x20` | |
| 2 | 8 | i | `0x22` | |
| 2 | 9 | o | `0x1F` | |
| 2 | 10 | p | `0x23` | |
| 2 | 11 | lbracket | `0x21` | EN: `[` `{` / RU: `х` `Х` |
| 2 | 12 | rbracket | `0x1E` | EN: `]` `}` / RU: `ъ` `Ъ` |
| 2 | 13 | backslash | `0x2A` | EN: `\` `\|` / RU: `\` `\|` |
| 3 | 1 | a | `0x00` | |
| 3 | 2 | s | `0x01` | |
| 3 | 3 | d | `0x02` | |
| 3 | 4 | f | `0x03` | |
| 3 | 5 | g | `0x05` | |
| 3 | 6 | h | `0x04` | |
| 3 | 7 | j | `0x26` | |
| 3 | 8 | k | `0x28` | |
| 3 | 9 | l | `0x25` | |
| 3 | 10 | semicolon | `0x29` | EN: `;` `:` / RU: `ж` `Ж` |
| 3 | 11 | quote | `0x27` | EN: `'` `"` / RU: `э` `Э` |
| 4 | 1 | z | `0x06` | |
| 4 | 2 | x | `0x07` | |
| 4 | 3 | c | `0x08` | |
| 4 | 4 | v | `0x09` | |
| 4 | 5 | b | `0x0B` | |
| 4 | 6 | n | `0x2D` | |
| 4 | 7 | m | `0x2E` | |
| 4 | 8 | comma | `0x2B` | EN: `,` `<` / RU: `б` `Б` |
| 4 | 9 | period | `0x2F` | EN: `.` `>` / RU: `ю` `Ю` |
| 4 | 10 | slash | `0x2C` | EN: `/` `?` / RU: `.` `,` |

**No manual mapper files are needed.** The mapper is auto-generated from the installed macOS keyboard layouts via `UCKeyTranslate`. To customize, simply click any key in the visual editor and pick the target character.

## Requirements

- **macOS 15.4 or later** (deployment target is `15.4`; the mapper window uses SwiftUI `Table` with `contextMenu(forSelectionType:)` and `.sheet(item:)`, which require macOS 13+, while several other modern SwiftUI APIs in the codebase need 15+)
- **Xcode 15.0 or later** (for building)
- An Apple ID signed into Xcode (free Personal Team is enough — see [Building](#building) below for the one-time signing setup)

## Permissions

EzSwitch requires the following permissions:

1. **Input Monitoring** — to detect double Shift and single Cmd taps
2. **Accessibility** — to transform selected text

To grant permissions:
1. Open **System Settings** → **Privacy & Security** → **Input Monitoring**
2. Add EzSwitch to the list
3. Open **System Settings** → **Privacy & Security** → **Accessibility**
4. Add EzSwitch to the list
5. Restart the application

## Installation

### Build from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/alexrel/EzSwitch.git
   cd EzSwitch
   ```

2. Build the project:
   ```bash
   ./build.sh
   ```

3. The built application will be in `build/Release/EzSwitch.app`

4. Copy to Applications:
   ```bash
   cp -r build/Release/EzSwitch.app /Applications/
   ```

## Usage

1. Launch EzSwitch — it will appear in your menu bar with a keyboard icon ⌨️
2. Click the icon to open settings (see screenshot above)
3. Configure your preferred options:
   - **Layout Switch**: pick the modifier family (Command or Option) and which language each side of the modifier switches to
   - **Text Transformation**: pick the double-tap key, whether to suppress it in apps, and whether to follow the result layout
   - **Launch at Login**: start EzSwitch automatically when you log in
   - **Keyboard Mappers**: open the mapper configuration window and the **Preset** dropdown selects which preset is active for the current pair

### Quick Layout Switching
- Tap **left Command** (or Option) → switch to the **Left** language
- Tap **right Command** (or Option) → switch to the **Right** language

### Text Transformation
1. Select text in any application (or place cursor after a word)
2. Double-tap the chosen key (Shift, Option, or any side)
3. The text will be transformed according to the active preset for the current language pair
4. If **Switch layout after** is on, the keyboard layout follows the result

### Hold One Shift + Double-Tap Other
If you hold one Shift key and double-tap the other, the transformation will occur without switching the keyboard layout.

### Configuring Mappers

1. Open EzSwitch settings → **Keyboard Mappers** → **Open**
2. In the mapper window, pick the **From** and **To** layouts from the dropdowns at the top
3. Switch between **Character Mappings** and **Word Substitutions** with the segmented control
4. **Character Mappings** tab: press **Auto** to instantly generate a complete mapping via macOS `UCKeyTranslate`. This works for any installed layouts and makes the new preset the active one for this pair
5. The visual keyboard below shows the current mapping — click any key to remap it via a popover picker

   <p align="center">
     <img src="screenshots/ezSwitch-mapper.png" alt="Mapper editor with visual keyboard" width="700">
   </p>

6. The **Map key** sheet lets you type any character, emoji, or a short string into the **Target** field — multi-character values are supported

   <p align="center">
     <img src="screenshots/ezSwitch-mapper-key.png" alt="Map key picker" width="700">
   </p>

7. The test row at the top lets you type text and see the result live
8. All changes are saved automatically to `~/Library/Application Support/EzSwitch/presets.json`
9. The reverse direction is built automatically (longest-match) — you only ever need to store one preset per language pair. For roundtrip-clean mapping, give each source key a unique target value (e.g. `е → "e"`, `э → "ë"`)
10. Use **New** to start from an empty preset, or the trash icon to delete the current one (a confirmation dialog guards against accidental loss)

### Word-Level Substitutions

1. Switch to the **Word Substitutions** tab
2. Type a word in any app (e.g. `пше` in Russian layout) and press the **remember hotkey** (default **⌘⇧M** — click the chip in the window header to rebind it). The current character mapping is applied to compute the equivalent in the other layout, the pair `пше → git` is stored for the active language direction, **and** the word is replaced in place
3. The same works on a **selected** word — press the hotkey with text selected and the selection is replaced with the mapped value (the entry is saved as well)
4. The keyboard layout is **not** changed during replacement — the new text is delivered via the system clipboard, so you stay in whatever layout you typed in
5. From now on, every time you finish typing `пше` (space, Enter, punctuation), it's auto-replaced with `git`
6. Case is preserved: `ОЫЩТ` → `JSON`, `Оыщт` → `Json`, `оыщт` → `json`
7. Toggle **Auto-replace** off to disable live replacement (the stored entries are kept, and the remember hotkey still trains + replaces manually)
8. Use **+** to add a manual entry, or check **Save both ways** in the add sheet to also store the reverse
9. Click **Edit** in any row to change its source or target — if you rename the source, the old entry is removed and the new one is saved. You can also **double-click** a row or **right-click** for the same Edit / Delete options
10. The trash icon next to each row removes a single entry; the header trash clears all entries for the current pair (with confirmation)
11. Stored in `~/Library/Application Support/EzSwitch/word_mappings.json`

All your custom presets and word mappings are saved to disk and persist across app restarts. The **Preset** dropdown in the popover lets you switch between presets for the current language pair without opening the mapper window.

## Architecture

The application consists of the following components (see `EzSwitch/*.swift` for full details):

- **AppDelegate**: Main application entry point, handles permissions and initialization
- **StatusBarController**: Manages the menu bar icon and settings popover
- **KeyboardManager**: Monitors keyboard events using CGEvent taps
- **TextTransformer**: Handles text transformation logic using the **active** preset selected in `SettingsManager`; the reverse direction is rebuilt on the fly via longest-match
- **ClipboardManager**: Manages clipboard state for copy/paste operations
- **SettingsManager**: Persists user preferences using UserDefaults, including the per-pair active preset ID
- **AppConfigRegistry**: Stores app-specific word selection configurations
- **PermissionsManager**: Handles Accessibility permission checks

- **MapperStore**: Persists `LayoutMapperPreset` objects to JSON
- **WordMapperStore**: Persists one-way word-level substitutions to JSON
- **WordMatcher**: Two-stage lookup (exact + lowercase fallback) with case restoration
- **MapperSettingsView** / **MapperEditorView** / **WordSubstitutionView**: UI for editing mappers (unified window — pick a pair + preset, then edit on the visual keyboard or manage word entries)
- **MapperWindowController**: Owns the standalone mapper configuration window
- **Constants.swift**: Single source of truth for all magic numbers and identifiers — `ModifierMask`, `KeyCode`, `UCTModifier`, `Timing` (double-tap threshold, paste delays, restore delays), `WordSub.minAutoReplaceLength`, `Default` (default languages, default hotkey), `DefaultsKey` (all UserDefaults keys), `FilePath`, `Unicode` (Cyrillic range), `ClipboardMarker`. New code should add constants here rather than hardcoding literals

### Mapper System

The text transformation uses a preset-based mapper system. Each `LayoutMapperPreset` covers a pair of layouts (e.g., "Russian – PC" → "ABC") and stores a character-to-string mapping (values can be one or many characters).

#### Active preset selection

`SettingsManager.selectedPresetIds["left|right"]` stores the active preset ID for the current language pair. The popover's **Preset** dropdown shows and changes this selection. The mapper window opens the same preset on launch and writes back to the same key when the user changes it there.

When transforming text:
- Forward (`left → right`) uses the active preset directly
- Reverse (`right → left`) is rebuilt from the active preset via `applyReverse` — see below

#### Files

```
EzSwitch/Mappers/
├── LayoutMapperPreset.swift        # Codable preset model
├── MapperStore.swift               # JSON-backed store of presets + first-launch auto-seed
└── KeyboardLayoutUtility.swift     # UCKeyTranslate wrapper + reverse-transformation helpers
```

#### How Auto-Generation Works

EzSwitch uses Apple's `UCKeyTranslate` Carbon API to look up what character a given key code produces in any installed keyboard layout, with any modifier state (none, Shift, Option, Shift+Option).

For each key code in the source layout, we look up the character it produces, then look up the character that the **same key code** produces in the target layout, and add a `sourceChar → targetChar` entry to the mapping.

This works for **any** pair of layouts installed in macOS, and covers all characters: lowercase, uppercase, digits, punctuation, special symbols (e.g., `№`, `€`, `«»`, etc.), and Shift-state characters.

**The mapper is auto-generated only.** There is no manual mapper file to write. Use the in-app **Auto** button in the mapper window to build a complete mapping for any installed layout pair in one click. To customize individual keys, click them in the visual editor and pick the target character.

#### How the Reverse Direction Works

`TextTransformer.applyReverse(_:forward:)` inverts the active mapping at transformation time. The inversion handles multi-character values correctly:

1. Forward entries with a multi-character value (e.g. `й → "ja"`) are stored as a list of patterns
2. Forward entries with a single-character value (e.g. `е → "e"`) populate a char-level map
3. Any char that is the *first* char of a multi-char pattern is **removed** from the char map — otherwise `"j"` would hijack `"ja"`
4. Multi-char patterns are tried longest-first at every position; char-level is the fallback

Roundtrip is exact when every source key has a unique target value. Collisions on the same target value (e.g. both `е → "e"` and `э → "e"`) are inherently ambiguous and resolve to whichever appears last in the active preset's iteration order. To get clean roundtrips, give colliding source keys distinct target values (e.g. `е → "e"`, `э → "ë"`).

## Building

### One-time setup: stable signing identity

By default, `xcodebuild` re-signs each build with a fresh adhoc identity, so
macOS treats every new build as a brand-new application and forces you to
re-grant **Accessibility** and **Input Monitoring** permissions every time.

To avoid this, set up a stable signing identity once:

```bash
./scripts/setup_dev_signing.sh
```

The script will detect existing certificates and, if none are found, print
step-by-step instructions. The recommended path is **Option A** (free
Personal Team via Apple ID — no paid account needed):

1. Xcode → Settings (⌘,) → **Accounts** tab
2. Click **+** → sign in with any Apple ID
3. Click **Manage Certificates** → **+** → **Apple Development**
4. Re-run `./scripts/setup_dev_signing.sh` to verify

After this, every `./build.sh` run will use the same signing identity, so
macOS will remember your permissions across builds.

### Using build.sh

```bash
# Build app + DMG (default)
./build.sh

# Build app only
./build.sh app

# Build DMG only (requires existing .app)
./build.sh dmg [path/to/EzSwitch.app]
```

### Using Xcode

1. Open `EzSwitch.xcodeproj` in Xcode
2. Select the EzSwitch scheme
3. Build and run (⌘R)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Uses Apple's Carbon and ApplicationServices frameworks for keyboard event handling
- Icon from SF Symbols (keyboard.fill)
