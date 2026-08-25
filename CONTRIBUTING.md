# Contributing

Issues and pull requests are welcome.

Before submitting a change:

1. Install the prerequisites described in the README.
2. Run `scripts/setup-vlc.sh` once.
3. Run `swift test`.
4. Build the application with `scripts/build-app.sh`.

Do not commit disc images, decrypted media, subtitles, MakeMKV components,
VLC binaries, build products, or personally identifying paths. Integration
tests that need a physical disc must use environment variables and skip cleanly
when the requested fixture is unavailable.
