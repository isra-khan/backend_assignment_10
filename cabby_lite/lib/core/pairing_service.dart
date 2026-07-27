import 'package:dio/dio.dart';

import '../models/captain.dart';
import 'api_client.dart';
import 'app_log.dart';

/// A freshly opened pairing. [code] is what gets rendered as the QR — verbatim.
class PairingCode {
  final String code;
  final DateTime? expiresAt;

  const PairingCode({required this.code, this.expiresAt});

  factory PairingCode.fromJson(Map<String, dynamic> json) => PairingCode(
        code: json['code']?.toString() ?? '',
        expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '')
            ?.toLocal(),
      );
}

enum PairingState { pending, expired, linked }

/// One reading of `/device/pair/status`.
class PairingStatus {
  final PairingState state;

  /// The device token. Non-null only on the *first* [PairingState.linked]
  /// response — the backend returns it once and every later poll returns null.
  final String? token;

  /// The captain who claimed this tablet, from the same response.
  final Captain? captain;

  const PairingStatus({required this.state, this.token, this.captain});

  factory PairingStatus.fromJson(Map<String, dynamic> json) {
    final raw = json['status']?.toString();
    final state = switch (raw) {
      'linked' => PairingState.linked,
      'expired' => PairingState.expired,
      _ => PairingState.pending,
    };
    final captainJson = json['captain'];
    return PairingStatus(
      state: state,
      token: json['token']?.toString(),
      // Bare Map, then copied — see the note in ActiveRide.fromJson. A tighter
      // check would cost the captain their profile on a re-encoded body.
      captain: captainJson is Map
          ? Captain.fromPairing(Map<String, dynamic>.from(captainJson))
          : null,
    );
  }
}

/// Raised when a pairing call fails in a way the loop can't interpret — a
/// network drop, a 5xx, a malformed body. The controller keeps retrying on
/// these rather than dumping the captain out of the flow.
class PairingException implements Exception {
  final String message;
  const PairingException(this.message);
  @override
  String toString() => message;
}

/// The two unauthenticated calls the tablet makes to get itself paired. The
/// third call in the flow — claiming the code — belongs to the captain's phone,
/// not here.
class PairingService {
  const PairingService();

  /// `POST /device/pair/start`. No auth: the tablet has no token yet.
  ///
  /// Sends `deviceId` only. `vehicleRegNo` and `fleetId` are optional on the
  /// wire and there is no MDM console to supply them — the backend fills the
  /// plate from the account of whichever captain scans, so an unprovisioned
  /// tablet still links correctly.
  Future<PairingCode> start(String deviceId) async {
    AppLog.info('pair', 'POST /device/pair/start deviceId=$deviceId');
    try {
      final res = await ApiClient.instance.dio.post<dynamic>(
        '/device/pair/start',
        data: {'deviceId': deviceId},
      );
      final data = res.data;
      if ((res.statusCode == 200 || res.statusCode == 201) &&
          data is Map<String, dynamic>) {
        final code = PairingCode.fromJson(data);
        if (code.code.isEmpty) {
          AppLog.error('pair', 'pair/start ${res.statusCode}: empty code');
          throw const PairingException('Server returned an empty pairing code');
        }
        AppLog.info(
          'pair',
          'pair/start ${res.statusCode} OK — code=${code.code} '
              'expires=${code.expiresAt?.toIso8601String() ?? 'n/a'}',
        );
        return code;
      }
      AppLog.error(
        'pair',
        'pair/start failed ${res.statusCode}: '
            '${ApiClient.messageFrom(res, 'no message')}',
      );
      throw PairingException(
        ApiClient.messageFrom(res, 'Could not start pairing'),
      );
    } on DioException catch (e) {
      AppLog.error('pair', 'pair/start network error', e.message);
      throw PairingException(
        ApiClient.messageFrom(e.response, 'No connection to the server'),
      );
    }
  }

  /// `GET /device/pair/status`. Polled every couple of seconds until a captain
  /// claims the code.
  Future<PairingStatus> status(String code, String deviceId) async {
    try {
      final res = await ApiClient.instance.dio.get<dynamic>(
        '/device/pair/status',
        queryParameters: {'code': code, 'deviceId': deviceId},
      );
      final data = res.data;
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        final status = PairingStatus.fromJson(data);
        // The linked case is the moment the tablet is claimed — log it loudly,
        // and note whether the token actually came through, since it is handed
        // out exactly once.
        if (status.state == PairingState.linked) {
          AppLog.info(
            'pair',
            'pair/status LINKED — captain=${status.captain?.name ?? 'unknown'} '
                'token=${status.token != null && status.token!.isNotEmpty ? 'received' : 'MISSING'}',
          );
        } else {
          // Pending is the common poll result; keep it quiet-but-present.
          AppLog.info('pair', 'pair/status ${status.state.name}');
        }
        return status;
      }
      // A 404/410 on a code the server has forgotten is an expiry, not a fault
      // — treat it as one so the screen offers a fresh code.
      if (res.statusCode == 404 || res.statusCode == 410) {
        AppLog.info('pair', 'pair/status ${res.statusCode}: code expired');
        return const PairingStatus(state: PairingState.expired);
      }
      AppLog.warn('pair', 'pair/status unexpected ${res.statusCode}');
      throw PairingException(
        ApiClient.messageFrom(res, 'Could not check pairing status'),
      );
    } on DioException catch (e) {
      AppLog.warn('pair', 'pair/status network error — ${e.message}');
      throw PairingException(
        ApiClient.messageFrom(e.response, 'No connection to the server'),
      );
    }
  }
}
