# Changelog

## [1.2.0] - 2026-06-26

### Added
- Theme system: blizzard (default), dark, minimal, neon, custom
- Bar texture override: flat, smooth, blizzard raid, or custom path
- Background alpha control
- Dock gap setting (space between docked windows)
- Hide docked headers option
- Show/hide peek hint toggle
- All visual elements now use dynamic theme colors
- Theme/bar/alpha/gap slash commands
- Theme selector in right-click menu

### Changed
- All colors are now Blizzard gold/amber scheme by default (matches native meter)
- Removed ugly background bar from peek hint — now shows only text + icons cleanly
- Smaller, cleaner arrow icons (12x12)
- Animations use theme colors dynamically

### Fixed
- Changing theme now immediately updates all visual elements
- Peek expand works on anchor window (uses FULLSCREEN_DIALOG strata)
- Taint error when trying to move locked windows (uses snap-back instead of SetMovable)

## [1.1.0] - 2026-06-24

### Added
- Peek Expand: drag up on top edge to temporarily see more meter bars
- Right-click context menu with inline icons
- Modern dock/undock animations (sweep line, dissolve effect)
- Pulsing snap preview with outer glow
- Undock button with smooth fade on hover

### Changed
- Renamed from DamageMeterPlus to MeterDock
- Docked windows now inherit both width AND height from anchor
- Lock system uses snap-back instead of SetMovable (prevents Blizzard taint)
- Prevents duplicate docks on the same side of the same target

### Fixed
- Circular anchor dependency errors on restore
- Taint errors when trying to move locked windows

## [1.0.0] - 2026-06-24

### Added
- Initial release
- Snap/dock meter windows (4 sides)
- Synced resize from anchor
- Options panel
- Slash commands
