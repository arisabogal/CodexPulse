# Contributing to CodexPulse

Thanks for considering a contribution.

## Development setup

1. Fork and clone the repo.
2. Open `CodexPulse.xcodeproj` in Xcode.
3. Build and run the `CodexPulse` scheme.
4. Run tests before opening a PR:

```bash
xcodebuild test -project CodexPulse.xcodeproj -scheme CodexPulse -destination 'platform=macOS'
```

## Pull request guidelines

- Keep PRs focused and small when possible.
- Add or update tests for behavior changes.
- Update docs if UX, setup, or behavior changes.
- Use clear commit messages.

## Issues

- For bugs, include reproduction steps, expected behavior, and actual behavior.
- For feature requests, include user value and a brief proposal.

## Code style

- Follow existing Swift and SwiftUI conventions in the repo.
- Prefer descriptive naming over comments.
- Keep view logic and data logic reasonably separated.

## Community

By participating, you agree to follow `CODE_OF_CONDUCT.md`.
