import 'dart:convert';
import 'package:supabase/supabase.dart';
import '../../core/config/supabase_config.dart';
import '../remote/api_client.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/order_repository.dart';
import '../local/database_helper.dart';

class OrderRepositoryImpl implements OrderRepository {
  static const String _fallbackReferenceId =
      '11111111-1111-4111-8111-111111111111';

  final DatabaseHelper _db;
  final SupabaseClient _supabase;

  OrderRepositoryImpl(
    this._db, {
    SupabaseClient? supabase,
  }) : _supabase = supabase ??
            SupabaseClient(SupabaseConfig.url, SupabaseConfig.anonKey);

  // ── Local writes ──────────────────────────────────────────────────────────

  @override
  Future<int> saveOrderLocally(Order order) async {
    final orderJson = order.toJson();
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
      'device_id': orderJson['device_id'],
      'schema_version': 1,
    });
    return _db.getPendingOrdersCount();
  }

  @override
  Future<int> deleteLocalOrder(String offlineId) async {
    await _db.deleteOrder(offlineId);
    return _db.getPendingOrdersCount();
  }

  @override
  Future<void> applyInventoryMovements({
    required List<CartItem> items,
    required String branchId,
    required String schoolId,
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    String? orderId,
  }) async {
    final supabase = _supabase;
    final createdById = await _resolveCreatedById();
    final totalAmount =
        items.fold<double>(0, (sum, item) => sum + item.lineTotal);

    final orderRes = await supabase
        .from('orders')
        .insert({
          'school_id': schoolId,
          'total_amount': totalAmount,
          'customer_name': customerName,
          'phone': customerPhone,
          'address': customerAddress,
          'payment_mode': 'UNKNOWN',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    final dbOrderId = orderRes['id'];
    print('ORDER CREATED: $dbOrderId');

    await supabase.from('order_items').insert(
          items
              .map((item) => {
                    'order_id': dbOrderId,
                    'variant_id': item.variant.id,
                    'quantity': item.quantity,
                    'price': item.variant.price,
                  })
              .toList(),
        );

    final inventoryReferenceSource = dbOrderId?.toString() ?? orderId;
    final quantitiesByVariant = <String, int>{};
    for (final item in items) {
      final quantity = item.quantity.abs();
      if (quantity <= 0) continue;
      quantitiesByVariant.update(
        item.variant.id,
        (current) => current + quantity,
        ifAbsent: () => quantity,
      );
    }

    final appliedEntries = <MapEntry<String, int>>[];

    try {
      for (final entry in quantitiesByVariant.entries) {
        final referenceId = _uuidOrFallback(inventoryReferenceSource);
        final res = await supabase.rpc(
          'apply_inventory_movement',
          params: {
            'p_branch_id': branchId,
            'p_variant_id': entry.key,
            'p_type': 'OUT',
            'p_quantity': entry.value,
            'p_reference_type': 'ORDER',
            'p_reference_id': referenceId,
            'p_reason': 'pos_order',
            'p_created_by': createdById,
          },
        );
        print('STOCK UPDATED: $res');
        appliedEntries.add(entry);
      }
    } catch (e) {
      print('CHECKOUT ERROR: $e');
      for (final entry in appliedEntries.reversed) {
        try {
          final rollbackReferenceId = _uuidOrFallback(inventoryReferenceSource);
          await supabase.rpc(
            'apply_inventory_movement',
            params: {
              'p_branch_id': branchId,
              'p_variant_id': entry.key,
              'p_type': 'IN',
              'p_quantity': entry.value,
              'p_reference_type': 'ORDER',
              'p_reference_id': rollbackReferenceId,
              'p_reason': 'pos_order_rollback',
              'p_created_by': createdById,
            },
          );
        } catch (rollbackError) {
          print(
              'CHECKOUT ERROR: rollback failed for ${entry.key}: $rollbackError');
        }
      }
      rethrow;
    }
  }

  String _uuidOrFallback(String? value) {
    final candidate = value?.trim();
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    if (candidate != null && uuidPattern.hasMatch(candidate)) {
      return candidate;
    }
    return _fallbackReferenceId;
  }

  Future<String?> _resolveCreatedById() async {
    final token = await ApiClient.getToken();
    if (token == null || token.isEmpty) return null;

    final parts = token.split('.');
    if (parts.length != 3) return null;

    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;

      final candidates = [
        payload['sub']?.toString(),
        payload['user_id']?.toString(),
        payload['profile_id']?.toString(),
      ];

      for (final candidate in candidates) {
        if (_isUuid(candidate)) return candidate;
      }
    } catch (_) {
      // Token is not JWT or payload is not decodable.
    }

    return null;
  }

  bool _isUuid(String? value) {
    if (value == null) return false;
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    return uuidPattern.hasMatch(value.trim());
  }

  // ── Remote sync ───────────────────────────────────────────────────────────

  @override
  Future<bool> syncOrder(Order order) async {
    try {
      final payload = await _syncPayload(order);
      await _supabase.from('orders').upsert(
            payload,
            onConflict: 'offline_id',
          );
      final response = await _supabase
          .from('orders')
          .select('id')
          .eq('offline_id', order.offlineId)
          .maybeSingle();

      final remoteId = _asInt(response?['id']);
      await _db.markSynced(order.offlineId, remoteId);
      order.syncStatus = OrderSyncStatus.synced;
      order.remoteId = remoteId;
      return true;
    } on PostgrestException catch (e) {
      await _db.markFailed(order.offlineId, e.message);
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
    final customerMap =
        jsonDecode(row['customer_json'] as String) as Map<String, dynamic>;

    return Order(
      offlineId: row['offline_id'] as String,
      customer: CustomerInfo.fromJson(customerMap),
      schoolId: row['school_id'].toString(),
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
    final customer =
        jsonDecode(row['customer_json'] as String) as Map<String, dynamic>;
    final items = (jsonDecode(row['items_json'] as String) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map((item) => {
              'product_id': item['product_id'],
              'variant_id': item['variant_id'],
              'quantity': item['quantity'],
              'price': item['price'] ?? item['unit_price'],
              'line_total': item['line_total'],
            })
        .toList();

    return {
      'offline_id': row['offline_id'],
      'school_id': row['school_id'],
      'customer': {
        'phone': customer['is_walk_in'] == true ? null : customer['phone'],
        'name': customer['name'],
        'is_walk_in': customer['is_walk_in'] ?? false,
      },
      'student': {
        'name': customer['student_name'],
        'class': customer['student_class'],
      },
      'items': items,
      'subtotal': row['subtotal'],
      'discount': row['discount_amount'],
      'total': row['total'],
      'payment_method': row['payment_method'],
      'created_at': row['created_at'],
      'device_id': row['device_id'],
      'schema_version': row['schema_version'] ?? 1,
    };
  }

  Future<Map<String, dynamic>> _syncPayload(Order order) async {
    if (order.items.isNotEmpty) return order.toJson();

    final row = await _db.getOrder(order.offlineId);
    if (row != null) return rawOrderJson(row);

    return order.toJson();
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
