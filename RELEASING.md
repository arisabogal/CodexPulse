# Releasing CodexPulse

This guide is for maintainers publishing a new GitHub release.

## 1. Prepare release contents

1. Update `CHANGELOG.md`.
2. Ensure `README.md` and screenshots are current.
3. Run a clean release build:

```bash
xcodebuild -project CodexPulse.xcodeproj -scheme CodexPulse -configuration Release -destination 'platform=macOS' -derivedDataPath .build-release build
```

4. Rebuild the downloadable app zip:

```bash
rm -f CodexPulse.app.zip
ditto -c -k --sequesterRsrc --keepParent .build-release/Build/Products/Release/CodexPulse.app CodexPulse.app.zip
```

## 2. Tag and push

1. Create an annotated tag (replace version as needed):

```bash
git tag -a v0.1.0 -m "CodexPulse v0.1.0"
```

2. Push branch and tag:

```bash
git push origin main
git push origin v0.1.0
```

## 3. Publish GitHub release

1. Open the repository Releases page.
2. Create a new release from the pushed tag.
3. Add release notes and highlights.
4. Upload `CodexPulse.app.zip` as a release asset.
5. Publish.
