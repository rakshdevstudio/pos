import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Global logout callback — set by main.dart so the interceptor can trigger
/// navigation without needing a BuildContext.
typedef LogoutCallback = void Function();
LogoutCallback? _onLogout;

void setGlobalLogoutCallback(LogoutCallback cb) => _onLogout = cb;

class ApiClient {
  static const String _baseUrlKey = 'api_base_url';
  static const String _defaultBaseUrl = 'https://api.illume.in/api/v1';
  static const String _tokenKey = 'auth_token';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  late final Dio _dio;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    _dio.interceptors.add(_AuthInterceptor());
    // LogInterceptor only in debug — strips sensitive data in production
    assert(() {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: false, // avoid logging full response bodies
        error: true,
      ));
      return true;
    }());
  }

  Dio get dio => _dio;

  // ── Base URL ──────────────────────────────────────────────────────────────

  static String _cachedBaseUrl = _defaultBaseUrl;

  static Future<void> initBaseUrl() async {
    final stored = await _storage.read(key: _baseUrlKey);
    _cachedBaseUrl = stored ?? _defaultBaseUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    _cachedBaseUrl = url;
    await _storage.write(key: _baseUrlKey, value: url);
  }

  static String get baseUrl => _cachedBaseUrl;

  // ── Token ─────────────────────────────────────────────────────────────────

  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    return _storage.read(key: _tokenKey);
  }

  static Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
  }
}

class _AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Synchronous base URL — no async SharedPreferences hit per request
    options.baseUrl = ApiClient.baseUrl;
    final token = await ApiClient.getToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      // Guard: don't loop on auth endpoints themselves
      final path = err.requestOptions.path;
      final isAuthPath = path.contains('/auth') || path.contains('/login');
      if (!isAuthPath) {
        ApiClient.clearToken();
        _onLogout?.call();
      }
    }
    handler.next(err);
  }
}
