import 'dart:io';
import 'cart_item.dart';
import 'customer_info.dart';

enum PaymentMethod { cash, upi, card, split }

enum OrderSyncStatus { pending, synced, failed }

class Order {
  final String offlineId;
  final CustomerInfo customer;
  final int schoolId;
  final List<CartItem> items;
  final double subtotal;
  final double discountAmount;
  final double total;
  final PaymentMethod paymentMethod;
  final DateTime createdAt;
  OrderSyncStatus syncStatus;
  int? remoteId;

  Order({
    required this.offlineId,
    required this.customer,
    required this.schoolId,
    required this.items,
    required this.subtotal,
    required this.discountAmount,
    required this.total,
    required this.paymentMethod,
    required this.createdAt,
    this.syncStatus = OrderSyncStatus.pending,
    this.remoteId,
  });

  /// Full backend payload — matches the agreed API contract exactly.
  Map<String, dynamic> toJson() => {
        'offline_id': offlineId,
        'school_id': schoolId,
        'customer': {
          'phone': customer.isWalkIn ? null : customer.phone,
          'name': customer.name,
          'is_walk_in': customer.isWalkIn,
        },
        'student': {
          'name': customer.studentName,
          'class': customer.studentClass,
        },
        'items': items
            .map((i) => {
                  'product_id': i.product.id,
                  'variant_id': i.variant.id,
                  'quantity': i.quantity,
                  'price': i.variant.price,
                  'line_total': i.lineTotal,
                })
            .toList(),
        'subtotal': subtotal,
        'discount': discountAmount,
        'total': total,
        'payment_method': paymentMethod.name,
        'created_at': createdAt.toIso8601String(),
        'device_id': _deviceId(),
        'schema_version': 1,
      };

  static String _deviceId() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'unknown';
    }
  }
}
