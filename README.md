# CodexPulse

CodexPulse is a macOS menu bar app that visualizes local Codex usage data from `~/.codex/sessions` as a heatmap, pacing summary, and shareable cards.

## Why this exists

When you work with Codex regularly, usage trends are hard to see from raw session files. CodexPulse turns that local telemetry into daily and weekly insights so you can track momentum and pacing.

## Features

- Menu bar app with fast access to usage metrics.
- Activity heatmap for recent days.
- Pacing panel with current tokens/hour and five-hour window status.
- Project filtering across scanned sessions.
- Shareable cards: `Build Highlights`, `Weekly Recap`, and `Build Mode`.
- Local-first scanning and caching for responsiveness.

## Privacy

- CodexPulse reads local session files from `~/.codex/sessions`.
- No server is required for core functionality.
- Data stays on your machine unless you explicitly share exported content.

## Requirements

- macOS 13.0+ (project currently configured with a `13.0` deployment target in Xcode settings).

## Quick download (no Xcode)

1. Open the repository's **Releases** page on GitHub.
2. Download the latest `CodexPulse.app.zip` asset.
3. Unzip it and drag `CodexPulse.app` into `/Applications`.
4. Launch the app from Applications.
5. If macOS warns that the app is from an unidentified developer, right-click the app, choose **Open**, then confirm.

## Build from source (developer setup)

1. Clone the repository.
2. Open `CodexPulse.xcodeproj` in Xcode.
3. Select the `CodexPulse` scheme.
4. Build and run.

## Testing

Run tests from Xcode, or use:

```bash
xcodebuild test -project CodexPulse.xcodeproj -scheme CodexPulse -destination 'platform=macOS'
```

## Releasing

Maintainer release steps live in `RELEASING.md`.

## Contributing

Contributions are welcome. Please read `CONTRIBUTING.md` before opening a PR.

## Security

Please report vulnerabilities using `SECURITY.md`.

## License

MIT. See `LICENSE`.
