# PME_TPE

Monorepo root.

## Structure

- `app/`: Flutter app
- `docs/`: project documentation (PDF / summaries)

## Local configuration (do not commit)

The app expects runtime config via `--dart-define` (recommended) or `--dart-define-from-file`.

Example:

```powershell
cd app
Copy-Item env.example.json env.json
flutter run --dart-define-from-file=env.json
```

Notes:
- `env.json` is ignored by git.
- On Web, set `FCM_VAPID_KEY` to enable Firebase Messaging token retrieval.
