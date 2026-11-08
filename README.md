# trackget

A small macOS app that downloads audio with yt-dlp, tags it and saves it to a folder.

## Build

Needs the Xcode Command Line Tools (Swift 6) and macOS 14 or later.

```sh
make app      # build build/trackget.app
make run      # build and open
make install  # copy to /Applications
```

## Tools

On first launch the app downloads its own tools to
`~/Library/Application Support/trackget/bin`. It does not use brew.

| Tool | Version | Update |
|---|---|---|
| yt-dlp | latest at install | checked on launch, updated with the toolbar button |
| ffmpeg, ffprobe | 9.0.2 (pinned, SHA-256 checked) | change `Tools.swift` |
| deno | latest at install | delete it to reinstall |

To reinstall all tools, delete the `bin` folder and launch the app again.

## License

Copyright (C) 2026 Shaw

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. See [LICENSE](LICENSE).
