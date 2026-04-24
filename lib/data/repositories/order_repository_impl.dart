import 'dart:convert';
import 'package:dio/dio.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/order_repository.dart';
import '../local/database_helper.dart';
import '../remote/api_client.dart';

class OrderRepositoryImpl implements OrderRepository {
  final ApiClient _apiClient;
  final DatabaseHelper _db;

  OrderRepositoryImpl(this._apiClient, this._db);

  // ── Local writes ──────────────────────────────────────────────────────────

  @override
  Future<int> saveOrderLocally(Order order) async {
    final now = DateTime.now().toIso8601String();
    await _db.insertOrder({
      'offline_id': order.offlineId,
      'school_id': order.schoolId,
      'customer_json': jsonEncode(order.customer.toJson()),
      'items_json': jsonEncode(
        order.items.map((i) => i.toOrderLine()).toList(),
      ),
      'subtotal': order.subtotal,
      'discount_amount': order.discountAmount,
      'total': order.total,
      'payment_method': order.paymentMethod.name,
      'created_at': order.createdAt.toIso8601String(),
      'updated_at': now,
      'sync_status': 'pending',
      'retry_count': 0,
      'schema_version': 1,
    });
    return _db.getPendingOrdersCount();
  }

  // ── Remote sync ───────────────────────────────────────────────────────────

  @override
  Future<bool> syncOrder(Order order) async {
    try {
      final baseUrl = ApiClient.baseUrl;
      final response = await _apiClient.dio.post(
        '$baseUrl/orders',
        data: order.toJson(),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final remoteId = response.data?['id'] as int?;
        await _db.markSynced(order.offlineId, remoteId);
        order.syncStatus = OrderSyncStatus.synced;
        order.remoteId = remoteId;
        return true;
      }

      await _db.markFailed(order.offlineId, 'HTTP ${response.statusCode}');
      order.syncStatus = OrderSyncStatus.failed;
      return false;
    } on DioException catch (e) {
      final status = e.response?.statusCode;

      // 409 = backend already has this order (idempotent) → treat as success
      if (status == 409) {
        final remoteId = e.response?.data?['id'] as int?;
        await _db.markSynced(order.offlineId, remoteId);
        order.syncStatus = OrderSyncStatus.synced;
        return true;
      }

      await _db.markFailed(order.offlineId, e.message ?? e.toString());
      order.syncStatus = OrderSyncStatus.failed;
      return false;
    } catch (e) {
      await _db.markFailed(order.offlineId, e.toString());
      order.syncStatus = OrderSyncStatus.failed;
      return false;
    }
  }

  // ── Queue reads ───────────────────────────────────────────────────────────

  @override
  Future<List<Order>> getPendingOrders() async {
    final rows = await _db.getPendingOrders();
    return rows.map(_rowToOrder).toList();
  }

  Future<int> getPendingOrdersCount() => _db.getPendingOrdersCount();

  // ── Helpers ───────────────────────────────────────────────────────────────

  Order _rowToOrder(Map<String, dynamic> row) {
    final customerMap = jsonDecode(row['customer_json'] as String) as Map<String, dynamic>;

    return Order(
      offlineId: row['offline_id'] as String,
      customer: CustomerInfo.fromJson(customerMap),
      schoolId: row['school_id'] as int,
      items: const [], // items are only needed for serialization; sync uses toJson()
      subtotal: (row['subtotal'] as num).toDouble(),
      discountAmount: (row['discount_amount'] as num).toDouble(),
      total: (row['total'] as num).toDouble(),
      paymentMethod: PaymentMethod.values.firstWhere(
        (m) => m.name == row['payment_method'],
        orElse: () => PaymentMethod.cash,
      ),
      createdAt: DateTime.parse(row['created_at'] as String),
      syncStatus: OrderSyncStatus.pending,
      remoteId: row['remote_id'] as int?,
    );
  }

  /// Returns a full JSON-serializable map for sync, using the stored JSON
  /// directly instead of re-constructing domain objects.
  Map<String, dynamic> rawOrderJson(Map<String, dynamic> row) {
    return {
      'offline_id': row['offline_id'],
      'school_id': row['school_id'],
      'customer': jsonDecode(row['customer_json'] as String),
      'items': jsonDecode(row['items_json'] as String),
      'subtotal': row['subtotal'],
      'discount': row['discount_amount'],
      'total': row['total'],
      'payment_method': row['payment_method'],
      'created_at': row['created_at'],
      'schema_version': row['schema_version'] ?? 1,
    };
  }
}
