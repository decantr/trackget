# TrackGet

A small macOS app that downloads audio with yt-dlp, tags it and saves it to a folder.

## Build

Needs the Xcode Command Line Tools (Swift 6) and macOS 14 or later.

```sh
make app      # build build/TrackGet.app
make run      # build and open
make install  # copy to /Applications
```

## Tools

On first launch the app downloads its own tools to
`~/Library/Application Support/trackget/bin`. It does not use brew.

| Tool | Version | Update |
|---|---|---|
| yt-dlp | latest folder build (SHA-256 checked) | checked on launch, re-downloaded with the toolbar button |
| ffmpeg, ffprobe | 9.0.2 (pinned, SHA-256 checked) | change `Tools.swift` |
| deno | latest at install | delete it to reinstall |

To reinstall all tools, delete the `bin` folder and launch the app again.

## Development

Tools are managed with [mise](https://mise.jdx.dev) (`actionlint`). Swift comes from Xcode.

```sh
make bootstrap  # install mise tools and resolve packages
make test       # needs Xcode, which ships Swift Testing
make lint       # check the GitHub workflows
make icon       # rebuild Resources/AppIcon.icns after editing AppIcon.svg
```

## Releasing

Push a signed tag on a signed commit:

```sh
git tag -s v0.1.0 -m v0.1.0
git push origin v0.1.0
```

The release workflow tests, builds and publishes `TrackGet.zip` with its SHA-256.
The app offers the update only when GitHub shows the tagged commit as verified.

## License

Copyright (C) 2026 Shaw

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. See [LICENSE](LICENSE).
