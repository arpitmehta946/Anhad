# Anhad mobile

Flutter client for Anhad. See `../docs/TECH_STACK.md` §2 for the full stack
reasoning and `../docs/FRONTEND_GUIDELINES.md` for design tokens; this is the
Phase 0 skeleton only (see `../docs/IMPLEMENTATION_PLAN.md`).

## First-time setup

Platform folders (`android/`, `ios/`, etc.) aren't checked in — they're
generated output, not source you hand-edit. Requires the Flutter SDK.

```sh
flutter create --platforms=android,ios --org com.anhad .
flutter pub get
flutter run
```

`flutter create` on an existing project only fills in what's missing
(platform folders); it won't touch `lib/` or this `pubspec.yaml`.

## Status

Phase 0: app shell, Dusk/Prabhat theme tokens, Riverpod wired in, a
placeholder feed screen. Phase 1 adds the real vertical `PageView` feed,
Isar-backed offline japa queue, and the volume-key MethodChannel.
