# EzSwitch settings design

## Platform and theme

Native macOS SwiftUI and AppKit. People configure a background keyboard utility at their desk in the same light or dark appearance as their other Mac applications. Follow system appearance using semantic window, control, and text colors.

## Layout

One resizable settings window with a 230-point sidebar, seven task-based sections, and a spacious content pane. Every page, including both rule editors, uses the same 24-point outer inset on all four sides, the same heading, and a 24-point gap before its content. SettingsLayout owns these values. Editor toolbars and scroll content align to that page grid and do not add their own horizontal page padding. Menu bar controls occupy a compact 360-point panel with the original opaque pale-blue gradient, colored feature icons, and separate control sections. Use an equivalent subdued gradient in dark appearance. Show a status message only when permissions need attention; do not add a routine ready label. About is an info button in the header and Quit is an explicit footer button, without an overflow menu.

Preference forms share a 250-point control column, aligned to the trailing edge. The row component owns this width so individual pickers cannot drift between pages.

The sidebar header centers the app icon and EzSwitch name together. Their left-to-right order and centered position stay fixed across interface languages.

The menu popover's gradient extends into its native arrow region. Menu action buttons use the same opaque background as the feature cards: white in light appearance, with an adaptive dark equivalent. Pressed buttons retain visible feedback.

## Typography and color

System typography: 27-point bold page title, 13-point body, 11–12-point secondary descriptions. Use the system accent for selection and actions. The sidebar footer uses primary text when permissions are granted and orange when attention is needed. Permission details keep green granted labels. The menu header has a compact green/orange permission indicator with an accessible label and tooltip.

## Components

Native buttons, switches, menus, and focus rings. All boolean controls use switches. In settings and sheets, switches precede their labels in a shared leading column; RTL mirrors the row. The settings window, rule editors, and sheets share the regular native control size. The menu bar panel also uses regular controls, with switches aligned at the trailing edge. Sidebar items have an SF Symbol, a title, and a brief description. Avoid decorative cards and gradients. Destructive commands have explicit labels or help text. Changes save automatically; app language changes apply immediately, including RTL layout, without resetting editor state.

Dropdowns share SettingsPicker: their native arrow changes sides immediately with the interface direction, and the selected title follows the leading edge (right in Hebrew). Only the popup is recreated on a direction change; its binding and surrounding editor state remain intact.

## Editors

Show the selected layout pair above each editor. Character presets apply to that pair; automatic word replacement is global. Keep physical keycaps left-to-right in every locale. Preserve confirmation dialogs for destructive operations.

Generated preset titles resolve layout names and their automatic suffix in the current interface language; custom titles remain verbatim. Generated-name metadata persists separately from the stored title, with exact-match recognition for legacy defaults.

Present editor sheets through LocalizedContent so their layout direction follows the app language independently of the system language. Hebrew places the source on the right and the target on the left, with left-pointing conversion arrows, mirrored action groups, and modifier choices beginning at the right edge. The physical keyboard grid stays left-to-right.
