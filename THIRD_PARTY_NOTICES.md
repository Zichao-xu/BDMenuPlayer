# Third-party notices

BD Menu Player interoperates with the following third-party components. They
are not authored by this project and remain subject to their own licenses.

## VLC / LibVLC

- Project: [VideoLAN VLC](https://www.videolan.org/vlc/)
- Runtime used by the release build: VLC 3.0.23 for Apple Silicon
- License information: [VideoLAN legal page](https://www.videolan.org/legal.html)
- Source: [VideoLAN source downloads](https://www.videolan.org/vlc/download-sources.html)

The application release bundle contains the official LibVLC runtime and
plugins. No modified VideoLAN binaries are distributed by this project.

## libbluray

- Project: [VideoLAN libbluray](https://www.videolan.org/developers/libbluray.html)
- License: LGPL-2.1-or-later
- Source: [VideoLAN libbluray repository](https://code.videolan.org/videolan/libbluray)

libbluray is a build and runtime prerequisite installed separately through
Homebrew. It is not included in the source repository or release archive.

## MakeMKV / libmmbd

- Project: [MakeMKV](https://www.makemkv.com/)
- License: proprietary; see the vendor's terms

MakeMKV is optional and user-installed. It is detected at runtime for discs
that require an AACS or BD+ backend. It is never bundled or redistributed by
this project.
