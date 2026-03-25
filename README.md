# EzSwitch

A macOS menu bar utility for keyboard layout switching and text transformation.

Inspired by Caramba Switcher and Karabiner-Elements

## Features

### Command Key Layout Switching
- Press **left Command** key → switch to left layout (configurable)
- Press **right Command** key → switch to right layout (configurable)
- Works as a quick tap (not holding)
- **Works with any pair of languages**, not just Russian and English

### Text Transformation
- Double-tap **Shift** (or **Option**) to transform selected text between keyboard layouts
- Works with selected text or the last word before cursor
- Supports various key combinations:
  - Double left/right Shift
  - Double left/right Option
  - Double any Shift/Option
- **Currently only supports Russian ↔ English transformation** (mapper system is extensible)

### Smart App Detection (work in progress)
- Automatically detects the current application
- Uses appropriate word selection method (Option+Shift+Left for macOS apps, Ctrl+Shift+Left for IDEs)
- Supports JetBrains IDEs, VS Code, browsers, and more

## Requirements

- macOS 11.0 or later
- Xcode 13.0 or later (for building)

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

### Option 1: Download DMG
1. Download the latest release from the [Releases](https://github.com/alexrel/EzSwitch/releases) page
2. Open the DMG file
3. Drag EzSwitch to your Applications folder
4. Launch EzSwitch from Applicationsyt dct cnhjrb gthtdtk yf 

### Option 2: Build from Source
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
2. Click the icon to open settings
3. Configure your preferred options:
   - **Command Switch**: Enable/disable quick layout switching with Command keys
   - **Text Transformation**: Enable/disable text transformation with double Shift/Option
   - **Launch at Login**: Start EzSwitch automatically when you log in

### Quick Layout Switching
- Tap **left Command** → switch to Russian
- Tap **right Command** → switch to English

### Text Transformation
1. Select text in any application (or place cursor after a word)
2. Double-tap **Shift** or **Option**
3. The text will be transformed between Russian and English layouts
4. The keyboard layout will automatically switch to match the result

### Hold One Shift + Double-Tap Other
If you hold one Shift key and double-tap the other, the transformation will occur without switching the keyboard layout.

## Architecture

The application consists of the following components:

- **AppDelegate**: Main application entry point, handles permissions and initialization
- **StatusBarController**: Manages the menu bar icon and settings popover
- **KeyboardManager**: Monitors keyboard events using CGEvent taps
- **TextTransformer**: Handles text transformation logic with dynamic mapper system
- **ClipboardManager**: Manages clipboard state for copy/paste operations
- **SettingsManager**: Persists user preferences using UserDefaults
- **AppConfigRegistry**: Stores app-specific word selection configurations
- **PermissionsManager**: Handles Accessibility permission checks

### Mapper System

The text transformation uses a dynamic mapper system located in `EzSwitch/Mappers/`:

```
EzSwitch/Mappers/
├── LayoutMapper.swift           # Protocol for all mappers
└── RussianToEnglishMapper.swift # Russian → English mapping
```

**To add a new language pair:**

1. Create a new mapper file (e.g., `GermanToEnglishMapper.swift`)
2. Implement the `LayoutMapper` protocol
3. Add it to `TextTransformer.initializeMappers()`
4. The reverse mapping is created automatically

Example:
```swift
struct GermanToEnglishMapper: LayoutMapper {
    let fromLayout = "German"
    let toLayout = "ABC"
    
    let mapping: [Character: Character] = [
        "y": "z", "z": "y",
        // ... rest of mapping
    ]
}
```

## Building

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