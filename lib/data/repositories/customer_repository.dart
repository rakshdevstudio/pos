import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/customer_info.dart';
import '../remote/api_client.dart';

class CustomerRepository {
  static const String _recentCustomersKey = 'recent_customers';
  final ApiClient _apiClient;

  CustomerRepository(this._apiClient);

  Future<List<CustomerInfo>> searchCustomers(String phone) async {
    // 1. Check local cache first
    final localMatches = await _getLocalMatches(phone);
    
    // 2. Search backend (simulated for now, replace with actual call if available)
    try {
      final response = await _apiClient.dio.get('/customers', queryParameters: {'phone': phone});
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        final remoteMatches = data.map((json) => CustomerInfo.fromJson(json)).toList();
        
        // Merge and deduplicate
        final all = [...localMatches];
        for (var remote in remoteMatches) {
          if (!all.any((l) => l.phone == remote.phone && l.studentName == remote.studentName)) {
            all.add(remote);
          }
        }
        return all;
      }
    } catch (e) {
      // Fallback to local only on error
    }

    return localMatches;
  }

  Future<List<CustomerInfo>> _getLocalMatches(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentCustomersKey);
    if (raw == null) return [];

    try {
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded
          .map((json) => CustomerInfo.fromJson(json))
          .where((c) => c.phone.contains(phone))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRecentCustomer(CustomerInfo customer) async {
    if (customer.isWalkIn) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentCustomersKey);
    List<CustomerInfo> existing = [];

    if (raw != null) {
      try {
        final List<dynamic> decoded = jsonDecode(raw);
        existing = decoded.map((json) => CustomerInfo.fromJson(json)).toList();
      } catch (_) {}
    }

    // Remove if already exists with same phone + student
    existing.removeWhere((c) => 
      c.phone == customer.phone && c.studentName == customer.studentName);
    
    // Insert at start
    existing.insert(0, customer);
    
    // Keep max 50
    if (existing.length > 50) existing = existing.sublist(0, 50);

    await prefs.setString(_recentCustomersKey, jsonEncode(existing.map((e) => e.toJson()).toList()));
  }
}
