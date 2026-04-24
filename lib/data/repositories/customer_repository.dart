import '../../domain/models/customer_info.dart';
import '../local/database_helper.dart';
import '../remote/api_client.dart';

class CustomerRepository {
  final ApiClient _apiClient;
  final DatabaseHelper _db;

  CustomerRepository(this._apiClient, this._db);

  /// Returns matching customers: local-first, then silent API merge.
  /// Caller gets local results immediately; UI can rebuild if remote adds more.
  Future<List<CustomerInfo>> searchCustomers(String phone) async {
    // 1. Immediate local results
    final localMatches = await _localSearch(phone);

    // 2. Silent async API fetch — no await, doesn't block caller
    _remoteSearch(phone);

    return localMatches;
  }

  Future<List<CustomerInfo>> _localSearch(String phone) async {
    final rows = await _db.searchCustomersCache(phone);
    return rows.map(CustomerInfo.fromJson).toList();
  }

  void _remoteSearch(String phone) {
    Future.microtask(() async {
      try {
        final baseUrl = ApiClient.baseUrl;
        final response = await _apiClient.dio.get(
          '$baseUrl/customers',
          queryParameters: {'phone': phone},
        );
        if (response.statusCode == 200 && response.data is List) {
          for (final item in response.data as List<dynamic>) {
            final map = item as Map<String, dynamic>;
            final phoneKey = (map['phone'] as String?) ?? phone;
            await _db.cacheCustomer(phoneKey, map);
          }
        }
      } catch (_) {
        // Offline — local results are sufficient
      }
    });
  }

  Future<void> saveRecentCustomer(CustomerInfo customer) async {
    if (customer.isWalkIn || customer.phone.isEmpty) return;
    await _db.cacheCustomer(customer.phone, customer.toJson());
  }
}
