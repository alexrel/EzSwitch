# EzSwitch

<p align="center">
  <img src="screenshots/icon.png" alt="EzSwitch Icon" width="128" height="128">
</p>

<p align="center">
  <strong>A macOS menu bar utility for keyboard layout switching, text transformation, and smart word substitution</strong>
</p>

<p align="center">
  Inspired by Caramba Switcher, Punto Switcher, and Karabiner-Elements
</p>

<p align="center">
  <img src="screenshots/ezSwitch-app.png" alt="EzSwitch Settings" width="380">
</p>

## Features

### Settings and Quick Controls
- A compact menu bar panel provides feature switches and a session-only pause that preserves saved preferences.
- One settings window contains General, Layout Switch, Text Transformation, Character Mappings, Word Substitutions, Permissions, and About.
- Open settings with **⌘,** while EzSwitch is active. Dictionary links open the pair assigned to the switch keys.
- General contains launch at login and interface language: system default, English, Russian, Ukrainian, or Hebrew. Language changes apply immediately, preserve editor state, and do not change keyboard layouts.
- Permissions shows Accessibility and Input Monitoring separately, with links to the corresponding macOS settings.
- Word substitutions include search and an explicit remember-shortcut button. Automatic replacement applies to all configured pairs; the dictionary editor shows only the selected pair.

### Command / Option Key Layout Switching
- Press **Left Command** key → switch to Left layout (configurable)
- Press **Right Command** key → switch to Right layout (configurable)
- Works as a quick single tap (holding the key for shortcuts like `⌘C` / `⌘V` does not switch layouts)
- **Works with any pair of languages**, not just Russian and English
- The modifier family (**Command** or **Option**) is selectable from the **Key** dropdown
- **Order-independent language pair**: swapping Left and Right languages keeps the exact same active preset, character mappings, and word substitutions

### Text Transformation & Multi-Language Cycling
- Double-tap **Shift** (or **Option**) to transform selected text or the last typed word between keyboard layouts
- Automatically detects the source language of the text and converts it to the opposite layout in your pair (`ghbdtn` ↔ `привет`)
- **Multi-Language Pivot & Cycling (3+ layouts, e.g. Hebrew, Spanish, etc.)**:
  - When typing in a 3rd layout (e.g. Hebrew), Double Shift intelligently cycles through your primary switcher layouts (`Russian`, `English`) using presets and layout history:
    - **1st press**: transforms to the layout you just came from (`previousLayout`, e.g. `Hebrew → Russian`)
    - **2nd press** (within 2.5s): transforms to the other primary layout (e.g. `Russian → English`, via direct or bridge mapping)
    - **3rd press** (within 2.5s): reverts back to the original text and layout (Undo)
  - Other unrelated languages (e.g. Spanish) never interfere unless actively typed
- Supports various trigger combinations:
  - Double Left / Right Shift
  - Double Left / Right Option
  - Double any Shift / Option
  - **Hold one Shift + double-tap the other** — transforms text without switching the active keyboard layout
- **Suppress in apps** toggle — blocks the double-tap from reaching apps where it triggers unwanted actions (e.g. JetBrains IDEs' *Search Everywhere* on double Shift)
- **Switch layout after** — automatically switches the active input source to match the transformed text

### Smart App Detection
- Automatically detects the frontmost application (`AppConfigRegistry`)
- Uses the appropriate word selection shortcut (`⌥⇧←` for native macOS apps, `⌃⇧←` for JetBrains IDEs, VS Code, Cursor, Zed, Windsurf, Sublime Text, Terminal apps, etc.)

### Customizable Keyboard Mappers (`Character Mappings`)
- **Unified Bidirectional Language Pair (`Russian – PC ↔ ABC`)** — one shared mapping and preset list per language pair regardless of which layout is assigned to Left or Right Command
- **Auto-generated** mappings via Apple's `UCKeyTranslate` Carbon API: select two layouts and click **Auto** (`✨`) to build a complete mapping from the system key code tables
- **Tactile Dual-Legend Visual Keyboard** — styled after Apple Magic Keyboard dual-legend keycaps (source character in top-left, mapped target character in bottom-right, with LED-lit `Shift` modifier caps); click any key to customize
- **Multi-character targets** — a single source key can map to a sequence (e.g. `й → "ja"`, `ц → "tz"`, emoji, or symbols)
- **Extra mappings** — custom source characters, including those typed with Option or Shift+Option, participate in explicit text correction and its preview. Enter the actual produced character as the source. Extra rules override ordinary mappings and support reverse conversion with multi-character targets.
- **Automatic reverse direction** — store only one preset per language pair; the opposite direction is rebuilt via longest-match (`TextTransformer.applyReverse`)
- **Confirmation guards** — clicking **Auto** (`✨`), **Clear all keys** (`🧹`), or **Delete preset** (`🗑`) prompts for confirmation before overwriting or deleting custom mappings
- **Live bidirectional test bar** — test your mapping in either direction directly above the keyboard without risking your saved keys
- Presets are stored in `~/Library/Application Support/EzSwitch/presets.json`

### Smart Word Substitutions (`Word Substitutions`)
- **Automatic word-level replacement** — teach EzSwitch words that you frequently mistype in the wrong layout (e.g. `ghbdtn → привет`, `пше → git`); as soon as you type a word (2+ characters) followed by Space, Enter, Tab, or punctuation, it is replaced in place
- **Target layout auto-switching** — each word substitution has an optional *"Switch keyboard layout to target language"* (`🌐 Switch layout`) toggle: when triggered, EzSwitch seamlessly changes macOS system input source to the target layout right after replacing the word, so you can keep typing without manual layout switching
- **Case preservation** — `ПШЕ` → `GIT`, `Пше` → `Git`, `пше` → `git`
- **Configurable Remember Hotkey** (default **⌘⌥M**) — type a word (or select an existing word) in any app and press the hotkey: EzSwitch converts the word in place **and** saves the substitution to your dictionary
- **Clear one-way mappings** — substitutions are strictly directional (`Source → Target`), avoiding accidental reverse-corruption of legitimate words; reverse rules can simply be added as separate entries if needed
- **Unified per-pair list** — all word substitutions for `Russian – PC ↔ ABC` live in a single unified table regardless of Left/Right Command order
- Stored in `~/Library/Application Support/EzSwitch/word_mappings.json`

#### Mapper Editor — Visual Keyboard Layout
The editor shows a 48-key QWERTY grid (4 rows × 14/13/11/10 keys) with decorative modifier keys (`Tab`, `Caps Lock`, `Return`, `Shift`). Each key displays its base and Shift-state mapping.

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
| 2 | 13 | backslash | `0x2A` | EN: `\` `\|` / RU: `\` `/` |
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

## Requirements

- **macOS 15.4 or later**
- **Xcode 15.0 or later** (if building from source)

## Permissions

EzSwitch requires two macOS permissions to monitor keys and replace text:

1. **Input Monitoring** — to detect single modifier taps, double Shift/Option taps, and typed word boundaries
2. **Accessibility** — to transform selected text and perform automatic word replacements

To grant permissions:
1. Open **System Settings** → **Privacy & Security** → **Input Monitoring** and enable **EzSwitch**
2. Open **System Settings** → **Privacy & Security** → **Accessibility** and enable **EzSwitch**
3. Open **Settings… → Permissions** and click **Restart** (or relaunch the app)

## Installation

### Option A: Install Pre-Built Release (`EzSwitch.dmg` or `EzSwitch-Portable.zip`)
1. Download `EzSwitch.dmg` or `EzSwitch-Portable.zip` from the [Releases](https://github.com/alexrel/EzSwitch/releases) page
2. Drag `EzSwitch.app` into your `/Applications` folder
3. Because the portable release uses an ad-hoc signature (without paid Apple notarization), macOS Gatekeeper may show an *"unidentified developer"* prompt on first launch:
   - Either go to **System Settings → Privacy & Security** and click **Open Anyway**
   - Or clear the quarantine attribute in Terminal:
     ```bash
     xattr -cr /Applications/EzSwitch.app
     open /Applications/EzSwitch.app
     ```
4. Grant **Input Monitoring** and **Accessibility** permissions when prompted

### Option B: Build from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/alexrel/EzSwitch.git
   cd EzSwitch
   ```
2. Build the project:
   ```bash
   ./build.sh
   ```
3. Install to `/Applications`:
   ```bash
   rm -rf /Applications/EzSwitch.app && cp -R build/Release/EzSwitch.app /Applications/ && open /Applications/EzSwitch.app
   ```

## Usage

1. Launch **EzSwitch** — a keyboard icon (`⌨️`) appears in your macOS menu bar
2. Click the icon to open quick controls. Enable or disable individual features, or pause EzSwitch without changing saved preferences.
3. Choose **Settings…** to configure the app:
   - **General**: launch at login and interface language
   - **Layout Switch**: Command/Option and the layouts assigned to each side
   - **Text Transformation**: double-tap key, event suppression, and layout switching after correction
   - **Character Mappings** and **Word Substitutions**: edit rules for a selected pair
   - **Permissions**: inspect both permissions, open their system settings, and restart if needed
   - **About EzSwitch**: version, build, author, and project link

### Configuring Mappers (`Character Mappings`)

1. Open EzSwitch settings → **Character Mappings**
2. Select your language pair at the top (`Russian – PC ↔ ABC`)
3. In the editor header:
   - Use the **Active preset** dropdown to switch between saved presets for the pair
   - Click **+ New** to create a custom preset
   - Click **Auto-generate** to automatically populate all keys from the installed macOS keyboard layouts via `UCKeyTranslate`
   - Click **Clear all keys** (`🧹`) to reset keys in the current preset, or **Delete preset** (`🗑`) to remove the preset
4. Click any keycap on the virtual keyboard (Base or `⇧ Shift` layer) to customize its target character or multi-character string

   <p align="center">
     <img src="screenshots/ezSwitch-mapper.png" alt="Mapper editor with visual keyboard" width="700">
   </p>

   <p align="center">
     <img src="screenshots/ezSwitch-mapper-key.png" alt="Map key picker" width="700">
   </p>

5. Use the **Test mapping** bar to preview transformations in either direction in real time

### Configuring Word Substitutions (`Word Substitutions`)

1. Open **Word Substitutions** in the settings sidebar, or choose **Dictionary…** in quick controls
2. **Quick training via Hotkey**: type a word in any app (e.g. `пше`) or select a word, then press **⌘⌥M** (customizable using the **Remember Word** button in the header). EzSwitch replaces the word with `git` in place and saves `пше → git` to your list
3. **Manual entry**: click **+ Add** to add a custom word pair. Check **Switch keyboard layout to target language** (`🌐 Switch layout`) if you want the system keyboard layout to automatically switch to the target language upon replacement
4. **Editing & Deleting**: click a row to modify the source/target word or toggle layout switching; click its trash button to delete the entry. Use the search field to find source or target words

## Architecture

The application is written in Swift & SwiftUI (`EzSwitch/*.swift`):

- **`AppDelegate`**: Application lifecycle, accessory activation policy (menu bar only), and initial permission checks
- **`StatusBarController`**: Manages the `NSStatusItem` and transient `NSPopover` hosting `QuickControlsView`
- **`SettingsWindowController`**: Owns the single settings window and routes direct links to the selected editor and layout pair
- **`SettingsView`**: Sidebar preferences, interface language, permissions, and embedded rule editors
- **`AppLocalization`**: Live translation bundles, system-language resolution, and locale updates that preserve editor state
- **`KeyboardManager`**: Monitors global key events via `CGEvent.tapCreate`, tracks single modifier taps, double-tap transform triggers, system layout changes (`kTISNotifySelectedKeyboardInputSourceChanged` for `previousLayout` tracking), and live word buffering for automatic substitutions
- **`TextTransformer`**: Transforms selected text or the last word before the cursor; features **Multi-Language Pivot & Cycling** with `previousLayout` priority and consecutive double-tap cycling across multiple layouts (with Undo on 3rd press)
- **`ClipboardManager`**: Preserves and restores the system `NSPasteboard` around synthetic `⌘C` / `⌘V` operations
- **`SettingsManager`**: Persists user settings in `UserDefaults`, including order-independent active preset selection (`selectedPresetId(for:_:)`)
- **`AppConfigRegistry`**: Per-application word selection shortcuts (`⌥⇧←` vs `⌃⇧←`) with bundle ID and keyword matching
- **`MapperStore`**: Thread-safe JSON store (`presets.json`) for `LayoutMapperPreset` models with bidirectional pair matching and first-launch auto-seeding
- **`WordMapperStore` & `WordMatcher`**: Unified per-pair JSON store (`word_mappings.json`) and case-preserving matcher for word-level substitutions with per-word target layout switching
- **`MapperSettingsView` / `MapperEditorView` / `WordSubstitutionView`**: Unified SwiftUI mapper window with tactile dual-legend keyboard keycaps, persistent layout pair selection, and modern word substitution management
- **`Constants`**: Centralized constants for key codes, modifier masks, timing intervals, UserDefaults keys, and minimum word replacement length (`Constants.WordSub.minAutoReplaceLength`)

## Building & Distribution

### Dual-Target `build.sh` (Local Dev + Portable Release)

Running `./build.sh` produces two types of artifacts:

1. **Local Development App (`build/Release/EzSwitch.app` and `./EzSwitch.app`)**
   - Automatically signed with your local Keychain certificate (`Apple Development` or self-signed `EzSwitch Local Dev`) so macOS TCC remembers your **Accessibility** and **Input Monitoring** permissions across rebuilds.
   - To set up a stable local certificate once, run:
     ```bash
     ./scripts/setup_dev_signing.sh
     ```
2. **Portable Distribution Artifacts (`build/EzSwitch.dmg`, `build/EzSwitch-Portable.zip`, `build/Portable/EzSwitch.app`)**
   - Automatically re-signed with a universal **ad-hoc signature (`--sign -`)** without personal Team ID restrictions, so the DMG and ZIP can be shared on GitHub Releases and launched on any other Mac.

```bash
# Build local app + portable ZIP + DMG (default)
./build.sh

# Build app only
./build.sh app

# Build DMG only (from existing .app)
./build.sh dmg [path/to/EzSwitch.app]
```

### Versioning

EzSwitch follows Semantic Versioning with automated build numbering:
- **Marketing Version** (`CFBundleShortVersionString`): Stored in `EzSwitch/Info.plist`. To inspect or bump the version across the project:
  ```bash
  # Check current version & build number
  ./scripts/bump_version.sh

  # Bump marketing version
  ./scripts/bump_version.sh 1.2.0
  ```
- **Build Number** (`CFBundleVersion`): Automatically derived from the Git commit count (`git rev-list --count HEAD`) on every build.
- **Git Commit Hash**: Embedded into the app bundle's `Info.plist` and displayed in **About EzSwitch** (`v1.1.0 (build 4 · f3c94bd)`).

## Author

**AlexReL** — [github.com/alexrel](https://github.com/alexrel)

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
