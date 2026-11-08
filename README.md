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
| yt-dlp | latest | `yt-dlp -U` on every launch |
| ffmpeg, ffprobe | 9.0.2 (pinned, SHA-256 checked) | change `Tools.swift` |
| deno | latest at install | delete it to reinstall |

To reinstall all tools, delete the `bin` folder and launch the app again.
