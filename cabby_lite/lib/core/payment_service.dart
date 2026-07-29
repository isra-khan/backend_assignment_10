import 'package:dio/dio.dart';

import 'api_client.dart';
import 'ride_service.dart' show DeviceRevokedException, RideException;

/// How a ride's fare was settled.
enum PaymentOutcome {
  /// The rider paid — by wallet through the QR, or cash the captain confirmed.
  paid,

  /// The captain flagged non-payment. Support picks it up; it never blocks the
  /// captain from taking the next ride.
  disputed,
}

/// One reading of `GET /ride/:id/payment`.
class PaymentStatus {
  /// What the rider owes, in [currency]'s minor-unit-free whole units (PKR).
  final int amount;
  final String currency;

  /// Raw backend status — `paid`, `unpaid`, `disputed`, …
  final String status;

  const PaymentStatus({
    this.amount = 0,
    this.currency = 'PKR',
    this.status = 'unpaid',
  });

  bool get isPaid => status == 'paid';
  bool get isDisputed => status == 'disputed';

  /// The settled outcome, or null while the fare is still outstanding.
  PaymentOutcome? get outcome => switch (status) {
        'paid' => PaymentOutcome.paid,
        'disputed' => PaymentOutcome.disputed,
        _ => null,
      };

  factory PaymentStatus.fromJson(Map<String, dynamic> json) => PaymentStatus(
        amount: _asInt(json['amount']) ?? 0,
        currency: json['currency']?.toString() ?? 'PKR',
        status: json['paymentStatus']?.toString() ?? 'unpaid',
      );

  static int? _asInt(dynamic v) => v is num
      ? v.round()
      : double.tryParse(v?.toString() ?? '')?.round();
}

/// The payment half of the tablet's backend contract.
///
/// This is the one place the tablet POSTs. Everywhere else it is receive-only,
/// but the captain confirming cash at the kerb is a deliberate action they take
/// — not telemetry — and the backend has no other way to learn it happened.
///
/// The backend also emits `payment-received` / `payment-disputed` over the
/// socket, but per the contract the HTTP response is authoritative: when both
/// arrive, this wins.
class PaymentService {
  const PaymentService();

  /// `GET /ride/:id/payment` — the authoritative amount and status.
  Future<PaymentStatus> status(String rideId) async {
    try {
      final res = await ApiClient.instance.dio.get<dynamic>(
        '/ride/$rideId/payment',
      );
      if (res.statusCode == 401) throw const DeviceRevokedException();

      final data = res.data;
      if (res.statusCode == 200 && data is Map<String, dynamic>) {
        return PaymentStatus.fromJson(data);
      }
      throw RideException(
        ApiClient.messageFrom(res, 'Could not read the payment status'),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) throw const DeviceRevokedException();
      throw RideException(
        ApiClient.messageFrom(e.response, 'No connection to the server'),
      );
    }
  }

  /// `POST /ride/:id/payment { status: "paid" }` — the captain took cash.
  Future<PaymentStatus> confirmCash(String rideId) =>
      _post(rideId, {'status': 'paid'});

  /// `POST /ride/:id/payment { status: "disputed" }` — the rider didn't pay.
  /// Flags the ride for support; deliberately never blocks the captain.
  Future<PaymentStatus> dispute(String rideId, {String? note}) => _post(rideId, {
        'status': 'disputed',
        if (note != null && note.isNotEmpty) 'note': note,
      });

  Future<PaymentStatus> _post(String rideId, Map<String, dynamic> body) async {
    try {
      final res = await ApiClient.instance.dio.post<dynamic>(
        '/ride/$rideId/payment',
        data: body,
      );
      if (res.statusCode == 401) throw const DeviceRevokedException();

      final data = res.data;
      final code = res.statusCode ?? 0;
      if (code >= 200 && code < 300) {
        // Some backends echo the updated record, some return a bare ack. Fall
        // back to the status we just asked for rather than failing the call.
        return data is Map<String, dynamic>
            ? PaymentStatus.fromJson(data)
            : PaymentStatus(status: body['status'] as String);
      }
      throw RideException(
        ApiClient.messageFrom(res, 'Could not record the payment'),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) throw const DeviceRevokedException();
      throw RideException(
        ApiClient.messageFrom(e.response, 'No connection to the server'),
      );
    }
  }
}
