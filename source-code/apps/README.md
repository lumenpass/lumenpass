# Apps

This repo contains multiple Flutter apps:

- `apps/desktop`: Desktop-focused LumenPass app (macOS/Windows/Linux)
- `apps/mobile`: Mobile-focused LumenPass app (iOS/Android)

Shared business/data code lives in `packages/` (notably `packages/lumenpass_core`).

LumenPass does not require an application account or subscription. The project is licensed under the [Mozilla Public License 2.0](../LICENSE); third-party files retain their own notices.

## Quick commands

Desktop:

```bash
cd apps/desktop
flutter pub get
flutter run -d macos
```

Mobile:

```bash
cd apps/mobile
flutter pub get
flutter run
```

