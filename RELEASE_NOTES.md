# BD Menu Player 0.1.0

The first public preview of a native Apple Silicon Blu-ray menu player for
macOS.

## Highlights

- Original HDMV disc menus with directional navigation and activation
- Native SwiftUI/AppKit interface with Liquid Glass playback controls
- Hardware-assisted H.264 playback through VideoToolbox and LibVLC
- External ASS, SSA, and SRT subtitles
- Automatic two-file subtitle composition for multi-episode main features
- Chapter navigation, seeking, volume, mute, keyboard shortcuts, and full screen
- Optional MakeMKV/libmmbd discovery for encrypted discs

## Requirements

- Apple Silicon Mac running macOS 26 or later
- Homebrew `libbluray` 1.5 or later
- MakeMKV installed separately when an encrypted disc requires it

This is an unsigned preview build. After downloading, macOS may require the
user to approve opening it from Privacy & Security settings.
