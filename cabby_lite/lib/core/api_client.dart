import 'package:dio/dio.dart';

import '../config/env.dart';
import 'device_token_store.dart';

/// Thin wrapper over Dio, ported from the Cabby phone app so both clients treat
/// the backend identically.
///
/// Two things matter here. The backend authenticates via a `token` HEADER, not
/// `Authorization: Bearer` — get that wrong and every authenticated call 401s.
/// And a 401 on this device means the captain revoked the tablet, so the stored
/// token is cleared here rather than at each call site; the app then falls back
/// to the pairing screen on its own.
class ApiClient {
  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: Env.serverUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        // Don't throw on 4xx — callers inspect status/message themselves.
        // The pairing poll depends on this: an expired code is a 4xx it has to
        // read, not an exception it has to catch.
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // The pairing calls are deliberately unauthenticated — the tablet has
          // no token until a captain claims it — so a null token is normal here
          // and simply means the header is omitted.
          final token = await DeviceTokenStore.token();
          if (token != null) options.headers['token'] = token;
          handler.next(options);
        },
        onResponse: (response, handler) async {
          if (response.statusCode == 401) {
            await DeviceTokenStore.clear();
          }
          handler.next(response);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._();
  late final Dio _dio;

  Dio get dio => _dio;

  /// Pulls the server's `{ message }` out of a response, falling back to a
  /// generic line.
  static String messageFrom(
    Response? res, [
    String fallback = 'Something went wrong',
  ]) {
    final data = res?.data;
    if (data is Map && data['message'] is String) return data['message'];
    if (data is List && data.isNotEmpty && data.first is Map) {
      return data.first['msg']?.toString() ?? fallback;
    }
    return fallback;
  }
}
