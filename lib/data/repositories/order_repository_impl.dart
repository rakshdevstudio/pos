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
    required String schoolName,
    required String customerName,
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
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final totalAmount = subtotal;
    final resolvedSchoolName = _trimToNull(schoolName) ?? 'Store';
    const platformSource = 'offline';
    const platformChannel = 'pos';
    const platformOrderSource = 'pos';
    const platformCreatedVia = 'pos_app';
    const platformBuyerType = 'Walk-in Customer';
    final orderItemsSnapshot = _buildOrderItemsSummary(
      items: items,
      schoolName: resolvedSchoolName,
    );

    final now = DateTime.now().toIso8601String();
    final payload = <String, dynamic>{
      'offline_id': _trimToNull(orderId),
      'school_id': schoolId,
      'school_name': resolvedSchoolName,
      'branch_id': _trimToNull(branchId),
      'subtotal': subtotal,
      'total_amount': totalAmount,
      'total': totalAmount,
      'customer_name': _trimToNull(customerName) ?? 'Walk-in Customer',
      'student_name': _trimToNull(studentName),
      'phone': _trimToNull(customerPhone),
      'alternate_phone': _trimToNull(alternatePhone),
      'email': _trimToNull(customerEmail),
      'address': _trimToNull(customerAddress),
      'city': _trimToNull(city),
      'pincode': _trimToNull(pincode),
      'grade': _trimToNull(grade),
      'class_name': _trimToNull(className),
      'source': platformSource,
      'channel': platformChannel,
      'order_source': platformOrderSource,
      'order_channel': platformChannel,
      'created_via': platformCreatedVia,
      'customer_type': platformBuyerType,
      'buyer_type': platformBuyerType,
      'status': _trimToNull(status) ?? 'Placed',
      'items': orderItemsSnapshot,
      'order_items': orderItemsSnapshot,
      'payment_mode': 'UNKNOWN',
      'created_at': now,
      'updated_at': now,
    };

    print('POS PLATFORM SOURCE: $platformSource');
    print('POS CHANNEL: $platformChannel');
    print('POS CUSTOMER_TYPE: $platformBuyerType');
    print(
      'POS CUSTOMER_NAME: ${_trimToNull(customerName) ?? 'Walk-in Customer'}',
    );
    print('POS FINAL ORDER PAYLOAD:');
    print(payload);

    final orderRes = await _insertOrderWithSchemaFallback(payload);

    final dbOrderId = orderRes['id'];
    print('ORDER CREATED: $dbOrderId');

    await _enforcePosSourceMetadataById(dbOrderId);

    try {
      final savedRow = await supabase
          .from('orders')
          .select('*')
          .eq('id', dbOrderId)
          .maybeSingle();
      if (savedRow != null) {
        print('POS ORDER SAVED ROW:');
        print(_savedOrderSummary(savedRow, payload));
      }
    } catch (e) {
      print('POS ORDER VERIFY WARN: $e');
    }

    await _insertOrderItemsWithSchemaFallback(
      items: items,
      orderId: dbOrderId,
      schoolId: schoolId,
      schoolName: resolvedSchoolName,
    );

    try {
      final savedItems = await supabase
          .from('order_items')
          .select('*')
          .eq('order_id', dbOrderId)
          .order('id');
      print('POS ORDER ITEM SAVED ROWS:');
      print(savedItems);
    } catch (e) {
      print('POS ORDER ITEM VERIFY WARN: $e');
    }

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
        print(
          'POS ORDER WARN: orders column "$missingColumn" not found, retrying without it.',
        );
        mutablePayload.remove(missingColumn);
      }
    }
  }

  Future<void> _enforcePosSourceMetadataById(dynamic orderId) async {
    if (orderId == null) return;

    final mutablePayload = <String, dynamic>{
      'source': 'offline',
      'channel': 'pos',
      'order_source': 'pos',
      'order_channel': 'pos',
      'created_via': 'pos_app',
      'customer_type': 'Walk-in Customer',
      'buyer_type': 'Walk-in Customer',
      'updated_at': DateTime.now().toIso8601String(),
    };

    while (mutablePayload.isNotEmpty) {
      try {
        await _supabase.from('orders').update(mutablePayload).eq('id', orderId);
        print('POS SOURCE ENFORCED FOR ORDER: $orderId');
        return;
      } on PostgrestException catch (e) {
        final missingColumn = _extractMissingOrdersColumn(e.message);
        if (missingColumn == null ||
            !mutablePayload.containsKey(missingColumn)) {
          print('POS SOURCE ENFORCE WARN: $e');
          return;
        }
        print(
          'POS SOURCE ENFORCE WARN: orders column "$missingColumn" not found, retrying without it.',
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
      print(
          'POS ORDER WARN: status enum rejected "Placed", retrying with "placed".');
      return true;
    }

    payload.remove('status');
    print(
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

        print(
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
    final productName = item.product.name.trim();
    final variantNameRaw = item.variant.name.trim();
    final variantDisplayName = _formatVariantLabel(variantNameRaw);
    final title = '$productName ($variantDisplayName)';
    final quantity = item.quantity;
    final unitPrice = item.variant.price;
    final lineTotal = item.lineTotal;

    final payload = <String, dynamic>{
      'order_id': orderId,
      'product_id': item.product.id,
      'variant_id': item.variant.id,
      'name': title,
      'title': title,
      'display_name': title,
      'product_name': productName,
      'variant_name': variantDisplayName,
      'size': variantNameRaw,
      'sku': item.variant.sku,
      'school_id': schoolId,
      'school_name': schoolName,
      'category': item.product.category,
      'image_url': item.product.imageUrl,
      'quantity': quantity,
      'unit_price': unitPrice,
      'price': unitPrice,
      'line_total': lineTotal,
      'product_snapshot': {
        'product_name': productName,
        'variant_name': variantDisplayName,
        'size': variantNameRaw,
        'school_name': schoolName,
        'image_url': item.product.imageUrl,
        'sku': item.variant.sku,
      },
    };

    print('POS ORDER ITEM PAYLOAD:');
    print(payload);
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

  String _formatVariantLabel(String variantName) {
    final trimmed = variantName.trim();
    if (trimmed.isEmpty) return 'Size';
    if (trimmed.toLowerCase().startsWith('size ')) return trimmed;
    return 'Size $trimmed';
  }

  List<Map<String, dynamic>> _buildOrderItemsSummary({
    required List<CartItem> items,
    required String schoolName,
  }) {
    return items.map(
      (item) {
        final productName = item.product.name.trim();
        final variantLabel = _formatVariantLabel(item.variant.name);
        return <String, dynamic>{
          'product_id': item.product.id,
          'product_name': productName,
          'variant_id': item.variant.id,
          'variant_name': variantLabel,
          'size': item.variant.name,
          'sku': item.variant.sku,
          'quantity': item.quantity,
          'unit_price': item.variant.price,
          'line_total': item.lineTotal,
          'school_name': schoolName,
          'category': item.product.category,
          'name': '$productName ($variantLabel)',
          'title': '$productName ($variantLabel)',
        };
      },
    ).toList();
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
      if (remoteId != null) {
        await _enforcePosSourceMetadataById(remoteId);
      }
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
              'product_name': item['product_name'],
              'variant_name': item['variant_name'],
              'size': item['size'],
              'sku': item['sku'],
              'school_id': item['school_id'],
              'school_name': item['school_name'],
              'category': item['category'],
              'image_url': item['image_url'],
              'quantity': item['quantity'],
              'price': item['price'] ?? item['unit_price'],
              'unit_price': item['unit_price'] ?? item['price'],
              'line_total': item['line_total'],
              'name': item['name'],
              'title': item['title'],
              'display_name': item['display_name'],
              'product_snapshot': item['product_snapshot'],
            })
        .toList();

    return {
      'offline_id': row['offline_id'],
      'school_id': row['school_id'],
      'customer': {
        'phone': customer['is_walk_in'] == true ? null : customer['phone'],
        'name': customer['name'],
        'alternate_phone': customer['alternate_phone'],
        'address': customer['address'],
        'city': customer['city'],
        'pincode': customer['pincode'],
        'is_walk_in': customer['is_walk_in'] ?? false,
      },
      'student': {
        'name': customer['student_name'],
        'class': customer['class_name'] ?? customer['student_class'],
        'class_name': customer['class_name'] ?? customer['student_class'],
        'grade': customer['grade'] ?? customer['student_class'],
      },
      'items': items,
      'subtotal': row['subtotal'],
      'discount': row['discount_amount'],
      'total': row['total'],
      'payment_method': row['payment_method'],
      'created_at': row['created_at'],
      'device_id': row['device_id'],
      'schema_version': row['schema_version'] ?? 1,
      'source': 'offline',
      'channel': 'pos',
      'order_source': 'pos',
      'order_channel': 'pos',
      'created_via': 'pos_app',
      'customer_type': 'Walk-in Customer',
      'buyer_type': 'Walk-in Customer',
    };
  }

  Future<Map<String, dynamic>> _syncPayload(Order order) async {
    if (order.items.isNotEmpty) {
      return _withPosSourceMetadata(order.toJson());
    }

    final row = await _db.getOrder(order.offlineId);
    if (row != null) return _withPosSourceMetadata(rawOrderJson(row));

    return _withPosSourceMetadata(order.toJson());
  }

  Map<String, dynamic> _withPosSourceMetadata(Map<String, dynamic> payload) {
    return {
      ...payload,
      'source': 'offline',
      'channel': 'pos',
      'order_source': 'pos',
      'order_channel': 'pos',
      'created_via': 'pos_app',
      'customer_type': 'Walk-in Customer',
      'buyer_type': 'Walk-in Customer',
    };
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
