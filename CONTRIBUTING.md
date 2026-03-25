# Contributing to EzSwitch

Thank you for your interest in contributing to EzSwitch! This document provides guidelines and information for contributors.

## How to Contribute

### Reporting Bugs

If you find a bug, please create an issue with the following information:

1. **Title**: A clear, descriptive title
2. **Description**: Detailed description of the bug
3. **Steps to Reproduce**: Step-by-step instructions to reproduce the issue
4. **Expected Behavior**: What you expected to happen
5. **Actual Behavior**: What actually happened
6. **Environment**:
   - macOS version
   - EzSwitch version
   - Keyboard layouts you're using

### Suggesting Features

Feature requests are welcome! Please create an issue with:

1. **Title**: Clear feature description
2. **Description**: Detailed explanation of the feature
3. **Use Case**: Why this feature would be useful
4. **Implementation Ideas**: If you have any suggestions

### Code Contributions

1. **Fork the Repository**
   ```bash
   git clone https://github.com/alexrel/EzSwitch.git
   cd EzSwitch
   ```

2. **Create a Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make Your Changes**
   - Follow the existing code style
   - Add comments for complex logic
   - Update documentation if needed

4. **Test Your Changes**
   - Build the project: `./build.sh app`
   - Test the functionality manually
   - Ensure no regressions

5. **Commit Your Changes**
   ```bash
   git add .
   git commit -m "Add: brief description of your changes"
   ```

6. **Push and Create Pull Request**
   ```bash
   git push origin feature/your-feature-name
   ```
   Then create a Pull Request on GitHub.

## Code Style Guidelines

### Swift Code Style

- Use 4 spaces for indentation
- Use descriptive variable and function names
- Add doc comments for public APIs
- Keep functions focused and reasonably sized
- Use Swift naming conventions (camelCase for variables, PascalCase for types)

### Example:

```swift
/// Handles keyboard event monitoring
final class KeyboardManager {
    static let shared = KeyboardManager()
    
    private var eventTap: CFMachPort?
    
    /// Start monitoring keyboard events
    /// - Parameter suppressEvents: If true, events will be suppressed
    func startMonitoring(suppressEvents: Bool = false) {
        // Implementation
    }
}
```

### Comments

- Use English for all comments
- Add inline comments for complex logic
- Use `// MARK:` sections for organization
- Document public APIs with doc comments

## Project Structure

```
EzSwitch/
├── EzSwitchApp.swift          # Main app entry point
├── AppDelegate.swift          # Application delegate
├── StatusBarController.swift  # Menu bar management
├── KeyboardManager.swift      # Keyboard event handling
├── TextTransformer.swift      # Text transformation logic
├── ClipboardManager.swift     # Clipboard operations
├── SettingsManager.swift      # Settings persistence
├── SettingsView.swift         # Settings UI
├── AppConfigs.swift          # App-specific configurations
├── PermissionsManager.swift   # Permission handling
└── Assets.xcassets/          # App icons and resources
```

## Testing

### Manual Testing

1. Build and run the app
2. Test Command key switching with both left and right Command
3. Test text transformation with selected text
4. Test text transformation with last word (no selection)
5. Test different keyboard layouts
6. Test in various applications (browsers, editors, etc.)

### Checklist Before Submitting

- [ ] Code compiles without errors
- [ ] App runs without crashes
- [ ] New features work as expected
- [ ] No regressions in existing functionality
- [ ] Comments are in English
- [ ] Documentation updated if needed

## Pull Request Guidelines

### PR Title Format

Use one of these prefixes:
- `Add:` for new features
- `Fix:` for bug fixes
- `Update:` for improvements
- `Docs:` for documentation changes
- `Refactor:` for code refactoring

Example: `Add: Support for German keyboard layout`

### PR Description

Include:
1. What changes were made
2. Why these changes were made
3. How to test the changes
4. Any related issues

## Getting Help

If you have questions or need help:
1. Check existing issues
2. Create a new issue with your question
3. Be patient and respectful

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow
- Follow the project's coding standards

## License

By contributing, you agree that your contributions will be licensed under the MIT License.