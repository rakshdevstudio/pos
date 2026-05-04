import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';
import '../../core/config/supabase_config.dart';
import '../remote/api_client.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/order_repository.dart';
import '../local/database_helper.dart';

enum _InventoryMovementDirection {
  outbound('OUT', 'pos_order'),
  inbound('IN', 'pos_order_rollback');

  const _InventoryMovementDirection(this.rpcType, this.reason);

  final String rpcType;
  final String reason;
}

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
      'metadata_json': jsonEncode({
        'payment_breakdown': order.resolvedPaymentBreakdown
            .map((entry) => entry.toJson())
            .toList(),
        'metadata': order.metadata,
      }),
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
    required String schoolName,
    required String customerName,
    required double subtotal,
    required double discountAmount,
    required double total,
    required PaymentMethod paymentMethod,
    List<PaymentAllocation> paymentBreakdown = const [],
    Map<String, dynamic>? metadata,
    String? customerPhone,
    String? alternatePhone,
    String? customerEmail,
    String? customerAddress,
    String? city,
    String? pincode,
    String? studentName,
    String? grade,
    String? className,
    String? source,
    String? orderChannel,
    String? customerType,
    String? status,
    String? orderId,
  }) async {
    if (items.isEmpty) {
      throw StateError('Cannot place POS order with no items');
    }

    final supabase = _supabase;
    final createdById = await _resolveCreatedById();
    final totalAmount = total;
    final resolvedPaymentBreakdown = paymentBreakdown.isNotEmpty
        ? paymentBreakdown
        : [
            PaymentAllocation(
              method: paymentMethod == PaymentMethod.split
                  ? PaymentMethod.cash
                  : paymentMethod,
              amount: total,
            ),
          ];
    final payload = _buildRemoteOrderPayload(
      schoolId: schoolId,
      branchId: branchId,
      customerName: customerName,
      customerPhone: customerPhone,
      alternatePhone: alternatePhone,
      customerEmail: customerEmail,
      customerAddress: customerAddress,
      city: city,
      pincode: pincode,
      studentName: studentName,
      grade: grade,
      className: className,
      totalAmount: totalAmount,
      paymentMethod: paymentMethod,
      paymentBreakdown: resolvedPaymentBreakdown,
      status: status,
    );

    debugPrint('POS FINAL ORDER PAYLOAD:');
    debugPrint('$payload');

    final orderRes = await _insertOrderWithSchemaFallback(payload);

    final dbOrderId = orderRes['id'];
    final inventoryReferenceSource = dbOrderId?.toString() ?? orderId;
    final appliedEntries = <MapEntry<String, int>>[];
    debugPrint('ORDER CREATED: $dbOrderId');

    try {
      try {
        final savedRow = await supabase
            .from('orders')
            .select('*')
            .eq('id', dbOrderId)
            .maybeSingle();
        if (savedRow != null) {
          debugPrint('POS ORDER SAVED ROW:');
          debugPrint('${_savedOrderSummary(savedRow, payload)}');
        }
      } catch (e) {
        debugPrint('POS ORDER VERIFY WARN: $e');
      }

      await _insertOrderItemsWithSchemaFallback(
        items: items,
        orderId: dbOrderId,
        schoolId: schoolId,
        schoolName: schoolName,
      );

      try {
        final savedItems = await supabase
            .from('order_items')
            .select('*')
            .eq('order_id', dbOrderId)
            .order('id');
        debugPrint('POS ORDER ITEM SAVED ROWS:');
        debugPrint('$savedItems');
      } catch (e) {
        debugPrint('POS ORDER ITEM VERIFY WARN: $e');
      }

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

      for (final entry in quantitiesByVariant.entries) {
        final referenceId = _uuidOrFallback(inventoryReferenceSource);
        final res = await _applyInventoryMovementWithFallback(
          branchId: branchId,
          variantId: entry.key,
          quantity: entry.value,
          direction: _InventoryMovementDirection.outbound,
          referenceId: referenceId,
          createdById: createdById,
        );
        debugPrint('STOCK UPDATED: $res');
        appliedEntries.add(entry);
      }

      final scopedOrderId = _trimToNull(orderId);
      if (scopedOrderId != null) {
        await _db.markSynced(scopedOrderId, null);
      }
    } catch (e) {
      debugPrint('CHECKOUT ERROR: $e');
      for (final entry in appliedEntries.reversed) {
        try {
          final rollbackReferenceId = _uuidOrFallback(inventoryReferenceSource);
          await _applyInventoryMovementWithFallback(
            branchId: branchId,
            variantId: entry.key,
            quantity: entry.value,
            direction: _InventoryMovementDirection.inbound,
            referenceId: rollbackReferenceId,
            createdById: createdById,
          );
        } catch (rollbackError) {
          debugPrint(
            'CHECKOUT ERROR: rollback failed for ${entry.key}: $rollbackError',
          );
        }
      }
      await _cleanupInsertedOrder(dbOrderId);
      rethrow;
    }
  }

  Map<String, dynamic> _buildRemoteOrderPayload({
    required String schoolId,
    required String branchId,
    required String customerName,
    required double totalAmount,
    required PaymentMethod paymentMethod,
    required List<PaymentAllocation> paymentBreakdown,
    String? customerPhone,
    String? alternatePhone,
    String? customerEmail,
    String? customerAddress,
    String? city,
    String? pincode,
    String? studentName,
    String? grade,
    String? className,
    String? status,
  }) {
    final now = DateTime.now().toIso8601String();
    final normalizedStudentClass = _normalizeStudentClass(
      className ?? grade,
    );
    return <String, dynamic>{
      'school_id': schoolId.trim(),
      'branch_id': _trimToNull(branchId),
      'customer_name': _trimToNull(customerName) ?? 'Walk-in Customer',
      'phone': _trimToNull(customerPhone),
      'alternate_phone': _trimToNull(alternatePhone),
      'email': _trimToNull(customerEmail),
      'address': _trimToNull(customerAddress) ?? '-',
      'city': _trimToNull(city),
      'pincode': _trimToNull(pincode),
      'student_name': _trimToNull(studentName),
      'grade': normalizedStudentClass,
      'student_class': normalizedStudentClass,
      'total_amount': totalAmount,
      'payment_mode': _resolveRemotePaymentMode(
        paymentMethod,
        paymentBreakdown,
      ),
      'status': _normalizeRemoteStatus(status),
      'created_at': now,
      'updated_at': now,
    }..removeWhere((_, value) => value == null);
  }

  String _resolveRemotePaymentMode(
    PaymentMethod paymentMethod,
    List<PaymentAllocation> paymentBreakdown,
  ) {
    final methods = paymentBreakdown.map((entry) => entry.method).toSet();
    final isOnlineOnly = methods.isNotEmpty &&
        methods.every(
          (method) =>
              method == PaymentMethod.upi || method == PaymentMethod.card,
        );

    if (paymentMethod == PaymentMethod.upi ||
        paymentMethod == PaymentMethod.card ||
        isOnlineOnly) {
      return 'ONLINE';
    }
    return 'UNKNOWN';
  }

  String _normalizeRemoteStatus(String? status) {
    final normalized = status?.trim().toUpperCase();
    if (normalized == null || normalized.isEmpty) {
      return 'PLACED';
    }
    return normalized;
  }

  String? _normalizeStudentClass(String? value) {
    final trimmed = _trimToNull(value);
    return trimmed?.toUpperCase();
  }

  Future<dynamic> _applyInventoryMovementWithFallback({
    required String branchId,
    required String variantId,
    required int quantity,
    required _InventoryMovementDirection direction,
    required String referenceId,
    required String? createdById,
  }) async {
    try {
      return await _supabase.rpc(
        'apply_inventory_movement',
        params: {
          'p_branch_id': branchId,
          'p_variant_id': variantId,
          'p_type': direction.rpcType,
          'p_quantity': quantity,
          'p_reference_type': 'ORDER',
          'p_reference_id': referenceId,
          'p_reason': direction.reason,
          'p_created_by': createdById,
        },
      );
    } on PostgrestException catch (error) {
      debugPrint(
        'POS INVENTORY WARN: RPC apply_inventory_movement failed, falling back to direct branch_inventory update. $error',
      );
      final updatedStock = await _applyDirectInventoryUpdate(
        branchId: branchId,
        variantId: variantId,
        quantity: quantity,
        direction: direction,
      );
      return {'fallback': 'branch_inventory', 'stock': updatedStock};
    }
  }

  Future<int> _applyDirectInventoryUpdate({
    required String branchId,
    required String variantId,
    required int quantity,
    required _InventoryMovementDirection direction,
  }) async {
    final row = await _supabase
        .from('branch_inventory')
        .select('stock')
        .eq('branch_id', branchId)
        .eq('variant_id', variantId)
        .maybeSingle();

    if (row == null) {
      throw StateError(
        'Branch inventory row not found for branch $branchId and variant $variantId',
      );
    }

    final currentStock = _asInt(row['stock']) ?? 0;
    final nextStock = direction == _InventoryMovementDirection.outbound
        ? currentStock - quantity
        : currentStock + quantity;

    if (nextStock < 0) {
      throw StateError(
        'Insufficient stock for variant $variantId in branch $branchId',
      );
    }

    await _supabase
        .from('branch_inventory')
        .update({'stock': nextStock})
        .eq('branch_id', branchId)
        .eq('variant_id', variantId);

    return nextStock;
  }

  Future<void> _cleanupInsertedOrder(dynamic orderId) async {
    if (orderId == null) {
      return;
    }

    try {
      await _supabase.from('order_items').delete().eq('order_id', orderId);
    } catch (error) {
      debugPrint(
          'POS CLEANUP WARN: could not delete order_items for $orderId: $error');
    }

    try {
      await _supabase.from('orders').delete().eq('id', orderId);
    } catch (error) {
      debugPrint('POS CLEANUP WARN: could not delete order $orderId: $error');
    }
  }

  Future<Map<String, dynamic>> _insertOrderWithSchemaFallback(
    Map<String, dynamic> payload,
  ) async {
    final mutablePayload = Map<String, dynamic>.from(payload)
      ..removeWhere((_, value) => value == null);

    while (true) {
      try {
        final inserted = await _supabase
            .from('orders')
            .insert(mutablePayload)
            .select()
            .single();
        return inserted;
      } on PostgrestException catch (e) {
        final missingColumn = _extractMissingOrdersColumn(e.message);
        if (missingColumn == null ||
            !mutablePayload.containsKey(missingColumn)) {
          final handledEnumError = _handleStatusEnumMismatch(
            mutablePayload,
            e.message,
          );
          if (!handledEnumError) {
            rethrow;
          }
          continue;
        }
        debugPrint(
          'POS ORDER WARN: orders column "$missingColumn" not found, retrying without it.',
        );
        mutablePayload.remove(missingColumn);
      }
    }
  }

  bool _handleStatusEnumMismatch(
    Map<String, dynamic> payload,
    String errorMessage,
  ) {
    final isStatusEnumError = errorMessage
        .contains('invalid input value for enum order_lifecycle_status');
    if (!isStatusEnumError || !payload.containsKey('status')) {
      return false;
    }

    final currentStatus = payload['status']?.toString();
    if (currentStatus == 'Placed') {
      payload['status'] = 'placed';
      debugPrint(
          'POS ORDER WARN: status enum rejected "Placed", retrying with "placed".');
      return true;
    }

    payload.remove('status');
    debugPrint(
        'POS ORDER WARN: status enum still incompatible, retrying without status.');
    return true;
  }

  String? _extractMissingOrdersColumn(String message) {
    final schemaCacheMatch =
        RegExp(r"Could not find the '([^']+)' column of 'orders'")
            .firstMatch(message);
    if (schemaCacheMatch != null) {
      return schemaCacheMatch.group(1);
    }

    final relationMatch =
        RegExp(r'column "([^"]+)" of relation "orders" does not exist')
            .firstMatch(message);
    if (relationMatch != null) {
      return relationMatch.group(1);
    }

    return null;
  }

  Map<String, dynamic> _savedOrderSummary(
    Map<String, dynamic> savedRow,
    Map<String, dynamic> attemptedPayload,
  ) {
    final summary = <String, dynamic>{};
    for (final key in attemptedPayload.keys) {
      if (savedRow.containsKey(key)) {
        summary[key] = savedRow[key];
      }
    }
    summary['id'] = savedRow['id'];
    return summary;
  }

  String? _trimToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _insertOrderItemsWithSchemaFallback({
    required List<CartItem> items,
    required dynamic orderId,
    required String schoolId,
    required String schoolName,
  }) async {
    final mutablePayloads = _buildOrderItemPayloads(
      items: items,
      orderId: orderId,
      schoolId: schoolId,
      schoolName: schoolName,
    );

    while (true) {
      try {
        await _supabase.from('order_items').insert(mutablePayloads);
        return;
      } on PostgrestException catch (e) {
        final missingColumn = _extractMissingOrderItemsColumn(e.message);
        if (missingColumn == null) rethrow;

        final removed = mutablePayloads.every((payload) {
          if (!payload.containsKey(missingColumn)) return true;
          payload.remove(missingColumn);
          return true;
        });
        if (!removed) rethrow;

        debugPrint(
          'POS ORDER WARN: order_items column "$missingColumn" not found, retrying without it.',
        );
      }
    }
  }

  Future<void> _insertStoredOrderItemsWithSchemaFallback({
    required List<Map<String, dynamic>> items,
    required dynamic orderId,
  }) async {
    final mutablePayloads = items
        .map(
          (item) => <String, dynamic>{
            'order_id': orderId,
            'product_id': item['product_id'],
            'variant_id': item['variant_id'],
            'quantity': item['quantity'],
            'price': item['price'] ?? item['unit_price'],
          }..removeWhere((_, value) => value == null),
        )
        .toList();

    while (true) {
      try {
        await _supabase.from('order_items').insert(mutablePayloads);
        return;
      } on PostgrestException catch (e) {
        final missingColumn = _extractMissingOrderItemsColumn(e.message);
        if (missingColumn == null) rethrow;

        for (final payload in mutablePayloads) {
          payload.remove(missingColumn);
        }

        debugPrint(
          'POS ORDER WARN: order_items column "$missingColumn" not found, retrying without it.',
        );
      }
    }
  }

  List<Map<String, dynamic>> _buildOrderItemPayloads({
    required List<CartItem> items,
    required dynamic orderId,
    required String schoolId,
    required String schoolName,
  }) {
    return items
        .map(
          (item) => _buildOrderItemPayload(
            item: item,
            orderId: orderId,
            schoolId: schoolId,
            schoolName: schoolName,
          ),
        )
        .toList();
  }

  Map<String, dynamic> _buildOrderItemPayload({
    required CartItem item,
    required dynamic orderId,
    required String schoolId,
    required String schoolName,
  }) {
    final quantity = item.quantity;
    final unitPrice = item.variant.price;

    final payload = <String, dynamic>{
      'order_id': orderId,
      'product_id': item.product.id,
      'variant_id': item.variant.id,
      'quantity': quantity,
      'price': unitPrice,
    };

    debugPrint('POS ORDER ITEM PAYLOAD:');
    debugPrint('$payload');
    return payload;
  }

  String? _extractMissingOrderItemsColumn(String message) {
    final schemaCacheMatch =
        RegExp(r"Could not find the '([^']+)' column of 'order_items'")
            .firstMatch(message);
    if (schemaCacheMatch != null) {
      return schemaCacheMatch.group(1);
    }

    final relationMatch =
        RegExp(r'column "([^"]+)" of relation "order_items" does not exist')
            .firstMatch(message);
    if (relationMatch != null) {
      return relationMatch.group(1);
    }

    return null;
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
      final row = await _db.getOrder(order.offlineId);
      if (row == null) {
        throw StateError('Local order row not found for ${order.offlineId}');
      }

      await _syncStoredOrderRow(order.offlineId, row);
      await _db.markSynced(order.offlineId, null);
      order.syncStatus = OrderSyncStatus.synced;
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

  Future<void> _syncStoredOrderRow(
    String offlineId,
    Map<String, dynamic> row,
  ) async {
    final customer =
        jsonDecode(row['customer_json'] as String) as Map<String, dynamic>;
    final items = (jsonDecode(row['items_json'] as String) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();
    final metadataRow = row['metadata_json']?.toString();
    final metadataJson = metadataRow == null || metadataRow.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(metadataRow) as Map<String, dynamic>;
    final metadata = metadataJson['metadata'] is Map<String, dynamic>
        ? metadataJson['metadata'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final paymentBreakdown =
        (metadataJson['payment_breakdown'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(PaymentAllocation.fromJson)
            .toList();
    final paymentMethod = PaymentMethod.values.firstWhere(
      (method) => method.name == row['payment_method'],
      orElse: () => PaymentMethod.cash,
    );

    final payload = _buildRemoteOrderPayload(
      schoolId: row['school_id'].toString(),
      branchId: metadata['branch_id']?.toString() ?? '',
      customerName: customer['name']?.toString() ??
          metadata['customer_name']?.toString() ??
          'Walk-in Customer',
      customerPhone:
          customer['is_walk_in'] == true ? null : customer['phone']?.toString(),
      alternatePhone: customer['alternate_phone']?.toString(),
      customerEmail: null,
      customerAddress: customer['address']?.toString(),
      city: customer['city']?.toString(),
      pincode: customer['pincode']?.toString(),
      studentName: customer['student_name']?.toString(),
      grade: customer['grade']?.toString() ??
          customer['student_class']?.toString(),
      className: customer['class_name']?.toString() ??
          customer['student_class']?.toString(),
      totalAmount: (row['total'] as num).toDouble(),
      paymentMethod: paymentMethod,
      paymentBreakdown: paymentBreakdown,
      status: 'PLACED',
    );

    final orderRes = await _insertOrderWithSchemaFallback(payload);
    final dbOrderId = orderRes['id'];
    final inventoryReferenceSource = dbOrderId?.toString() ?? offlineId;

    try {
      await _insertStoredOrderItemsWithSchemaFallback(
        items: items,
        orderId: dbOrderId,
      );

      final quantitiesByVariant = <String, int>{};
      for (final item in items) {
        final variantId = item['variant_id']?.toString();
        if (variantId == null || variantId.isEmpty) continue;
        final quantity = _asInt(item['quantity']) ?? 0;
        if (quantity <= 0) continue;
        quantitiesByVariant.update(
          variantId,
          (current) => current + quantity,
          ifAbsent: () => quantity,
        );
      }

      for (final entry in quantitiesByVariant.entries) {
        await _applyInventoryMovementWithFallback(
          branchId: metadata['branch_id']?.toString() ?? '',
          variantId: entry.key,
          quantity: entry.value,
          direction: _InventoryMovementDirection.outbound,
          referenceId: _uuidOrFallback(inventoryReferenceSource),
          createdById: await _resolveCreatedById(),
        );
      }
    } catch (error) {
      await _cleanupInsertedOrder(dbOrderId);
      rethrow;
    }
  }

  Order _rowToOrder(Map<String, dynamic> row) {
    final customerMap =
        jsonDecode(row['customer_json'] as String) as Map<String, dynamic>;
    final metadataRow = row['metadata_json']?.toString();
    final metadataJson = metadataRow == null || metadataRow.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(metadataRow) as Map<String, dynamic>;
    final paymentBreakdownJson =
        (metadataJson['payment_breakdown'] as List<dynamic>? ?? const []);
    final orderMetadata = metadataJson['metadata'] is Map<String, dynamic>
        ? metadataJson['metadata'] as Map<String, dynamic>
        : const <String, dynamic>{};

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
      paymentBreakdown: paymentBreakdownJson
          .whereType<Map<String, dynamic>>()
          .map(PaymentAllocation.fromJson)
          .toList(),
      metadata: orderMetadata,
      createdAt: DateTime.parse(row['created_at'] as String),
      syncStatus: OrderSyncStatus.pending,
      remoteId: row['remote_id'] as int?,
    );
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
