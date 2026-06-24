# Changelog

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
