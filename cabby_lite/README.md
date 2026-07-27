# Cabby Lite

The in-car tablet companion to the Cabby captain app. It pairs to a captain's
account once, then spends its life on one of three screens: standby, the live
navigation map, and the fare summary at drop-off.

**Cabby Lite is a receive-only device.** It never emits a socket event and never
posts a location. Everything it shows comes from `GET /captain/active-ride` and
the socket feed.

## How it works

### 1. Pairing (once per tablet)

The tablet renders a QR code; the captain scans it on their phone.

```
tablet  POST /device/pair/start   { deviceId, vehicleRegNo?, fleetId? }
        → { code, expiresAt }                      code expires in 5 min

phone   scans the QR, claims the code                    (the phone app's side)

tablet  GET /device/pair/status?code=…&deviceId=…        polled every 2s
        → { status: "linked", token, captain }
```

The QR encodes the code string **exactly** as returned — no JSON wrapper, no
URL, no prefix. The phone posts whatever it decodes straight back, so anything
wrapped around it breaks the link.

The device token lasts a year and is stored in the keystore. No re-scan per day,
none per ride. Any `401` means the captain unlinked this tablet, so the token is
wiped and the app returns to the QR screen.

`deviceId`, `vehicleRegNo`, and `fleetId` come from Android Enterprise managed
configuration. Only `deviceId` is required — without managed config the app
generates one and persists it across reinstalls ([device_id.dart](lib/core/device_id.dart)).

### 2. Boot / ignition cycle

One call rebuilds the whole screen:

```
GET /captain/active-ride     header: token: <device token>
```

`ride: null` with a 200 means idle — show standby. It is not an error.

This is the authority. A tablet that was off or out of signal has missed every
event in the gap, so this snapshot always wins over whatever is on screen.

### 3. Live feed

```dart
io(serverUrl, { auth: { token: <device token> } })
```

| Event | Effect |
|---|---|
| `bid-accepted` / `ride-confirmed` | ride assigned — leave standby |
| `ride-started` | switch to the navigation map |
| `ride-ended` | fare + payment QR (payload carries the final fare) |
| `ride-cancelled` | back to standby |
| `my-location` | move the car marker (tracker vehicles only) |
| `new-ride`, `ride-taken` | ignored — the phone's request feed |

After any reconnect the app re-fetches `/captain/active-ride` rather than
assuming the screen is still right.

### Where the car marker comes from

Two modes, chosen by `locationSource` in the active-ride response:

- **`gps`** — the tablet's own GPS drives the marker, and `my-location` events
  are ignored entirely.
- **`tracker`** — the vehicle's hardware tracker does, arriving over
  `my-location` roughly every 10s. The tablet's own GPS is the wrong source here
  and is ignored.

`locationSource` is unknown until the backend answers. The map re-decides its
source on every fix rather than once at map-ready, so a `ride-started` that
arrives before the first sync still ends up following the right one.

## Setup

```bash
flutter pub get
```

Create `lib/.env`:

```
MAPBOX_TOKEN=pk.your_mapbox_public_token
SERVER_URL=https://your-dev-server
```

> ⚠️ `lib/.env` is currently **not** gitignored and holds a live Mapbox token.
> Add it to `.gitignore` before the first push, and rotate the token if it has
> already been committed.

`SERVER_URL` falls back to staging when absent — an in-car tablet has no
localhost worth talking to. Under MDM this comes from managed configuration
rather than the bundle.

```bash
flutter run
flutter test
flutter analyze
```

Launcher icons are shared with the main Cabby app. To regenerate after changing
`assets/icon/`:

```bash
dart run flutter_launcher_icons
```

## Testing without MDM or the phone app

The Linked Devices screen on the phone app isn't built yet, so nothing can scan
the tablet's QR. Stand in for it with curl.

```bash
# 1. Log in as a captain (stands in for the driver's phone)
curl -s -X POST https://<dev-server>/captain/login \
  -H "Content-Type: application/json" \
  -d '{"email":"<captain email>","password":"<password>"}'

# 2. Claim the code the tablet is showing (stands in for the QR scan)
curl -s -X POST https://<dev-server>/captain/devices/link \
  -H "Content-Type: application/json" \
  -H "token: <captain token>" \
  -d '{"code":"<the code on screen>"}'
```

The tablet's poll flips from `pending` to `linked` and takes the device token
from there.

```bash
# list linked tablets
curl -s https://<dev-server>/captain/devices -H "token: <captain token>"

# unlink — also how you test the revoked path
curl -s -X DELETE https://<dev-server>/captain/devices/<device _id> \
  -H "token: <captain token>"
```

Unlinking makes the device token start returning `401` and the socket refuse, so
the app should wipe the token and return to the QR screen.

### Watching the feed

Every socket event and phase transition logs in debug builds:

```bash
flutter logs | grep -E "\[socket\]|\[ride\]"
```

```
[socket] connected
[socket] ride-started  {ride: {…}}
[ride]   started → startTrip(68f2…) phase=RidePhase.welcome→inProgress
```

A `my-location` payload that fails to parse logs as `DROPPED — unparseable`,
so a schema mismatch doesn't fail silently.

## Layout

```
lib/
  config/     env, theme, palette, responsive layout tokens
  core/       API client, pairing + ride services, socket, device id/token
  models/     Captain, Trip, GeoPoint
  screens/    device_pairing · welcome · ride_in_progress · ride_summary
  state/      PairingController, RideController, LocationService
  widgets/    shared UI pieces
```

`CaptainHomeShell` routes between the three ride faces off `RidePhase`;
`RideController` owns the whole session and is the only thing the screens read.

### Coordinate order

`pickupLocation`, `destinationLocation`, and `captainPosition` are `{lat, lng}`.
`locationHistory` is GeoJSON `[lng, lat]` — **longitude first**. Mixing them up
puts the trail in the wrong hemisphere. There are two separate constructors in
[trip.dart](lib/models/trip.dart) precisely so these don't get crossed.

## Not built yet

- The payment QR payload endpoint and confirm-payment-received endpoint don't
  exist. The completion screen is built against the fare in the `ride-ended`
  payload for now.
- The captain profile is only ever set at pairing — `/captain/active-ride`
  returns no captain object, so the name on the standby screen never refreshes
  after linking.
