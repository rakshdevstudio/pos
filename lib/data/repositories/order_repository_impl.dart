import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/order_repository.dart';
import '../remote/api_client.dart';

class OrderRepositoryImpl implements OrderRepository {
  static const String _pendingOrdersKey = 'pending_orders';
  final ApiClient _apiClient;

  OrderRepositoryImpl(this._apiClient);

  Future<int> getPendingOrdersCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingOrdersKey);
    if (raw == null) return 0;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.length;
    } catch (_) {}
    return 0;
  }

  @override
  Future<int> saveOrderLocally(Order order) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingOrdersKey);
    List<dynamic> existing = [];
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) existing = decoded;
      } catch (_) {}
    }
    
    // Future-proof schema version wrapper
    existing.add({
      'version': 1,
      'payload': _orderToStorageMap(order),
    });
    
    await prefs.setString(_pendingOrdersKey, jsonEncode(existing));
    return existing.length;
  }

  @override
  Future<bool> syncOrder(Order order) async {
    try {
      final baseUrl = await ApiClient.getBaseUrl();
      final response = await _apiClient.dio.post(
        '$baseUrl/orders',
        data: order.toJson(),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        order.syncStatus = OrderSyncStatus.synced;
        order.remoteId = response.data['id'] as int?;
        return true;
      }
      return false;
    } catch (_) {
      order.syncStatus = OrderSyncStatus.failed;
      return false;
    }
  }

  @override
  Future<List<Order>> getPendingOrders() async {
    // Returns deserialized orders stored locally — simplified here
    return [];
  }

  Map<String, dynamic> _orderToStorageMap(Order order) {
    return {
      'offline_id': order.offlineId,
      'school_id': order.schoolId,
      'subtotal': order.subtotal,
      'discount_amount': order.discountAmount,
      'total': order.total,
      'payment_method': order.paymentMethod.name,
      'created_at': order.createdAt.toIso8601String(),
      'sync_status': order.syncStatus.name,
      'items': order.items.map((i) => i.toOrderLine()).toList(),
    };
  }
}
