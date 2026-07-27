# Cabby Lite

The in-car tablet companion to the Cabby captain app. It pairs to a captain's
account once via a QR code, then shows standby, the live navigation map during a
ride, and the fare summary at drop-off.

The tablet is a receive-only device — it never emits a socket event and never
posts a location.

## Configuration

Create `lib/.env`:

```
MAPBOX_TOKEN=pk.your_mapbox_public_token
SERVER_URL=https://your-dev-server
```

`SERVER_URL` falls back to staging when absent. Under MDM both values come from
Android Enterprise managed configuration rather than the bundle.

> ⚠️ `lib/.env` is not gitignored and holds a live Mapbox token. Add it to
> `.gitignore` before pushing, and rotate the token if it has already been
> committed.

## Running

```bash
flutter pub get
flutter run
```
