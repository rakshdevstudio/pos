import 'dart:io';
import 'cart_item.dart';
import 'customer_info.dart';

enum PaymentMethod { cash, upi, card, split }

extension PaymentMethodX on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.upi:
        return 'UPI';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.split:
        return 'Mixed';
    }
  }
}

class PaymentAllocation {
  final PaymentMethod method;
  final double amount;

  const PaymentAllocation({
    required this.method,
    required this.amount,
  });

  Map<String, dynamic> toJson() => {
        'method': method.name,
        'label': method.label,
        'amount': amount,
      };

  factory PaymentAllocation.fromJson(Map<String, dynamic> json) {
    final methodName = json['method']?.toString();
    return PaymentAllocation(
      method: PaymentMethod.values.firstWhere(
        (method) => method.name == methodName,
        orElse: () => PaymentMethod.cash,
      ),
      amount: _asDouble(json['amount']),
    );
  }

  static double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

enum OrderSyncStatus { pending, synced, failed }

class Order {
  final String offlineId;
  final CustomerInfo customer;
  final String schoolId;
  final List<CartItem> items;
  final double subtotal;
  final double discountAmount;
  final double total;
  final PaymentMethod paymentMethod;
  final List<PaymentAllocation> paymentBreakdown;
  final Map<String, dynamic> metadata;
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
    this.paymentBreakdown = const [],
    this.metadata = const {},
    required this.createdAt,
    this.syncStatus = OrderSyncStatus.pending,
    this.remoteId,
  });

  List<PaymentAllocation> get resolvedPaymentBreakdown {
    if (paymentBreakdown.isNotEmpty) {
      return paymentBreakdown;
    }
    return [
      PaymentAllocation(
        method: paymentMethod == PaymentMethod.split
            ? PaymentMethod.cash
            : paymentMethod,
        amount: total,
      ),
    ];
  }

  /// Full backend payload — matches the agreed API contract exactly.
  Map<String, dynamic> toJson() => {
        'offline_id': offlineId,
        'school_id': schoolId,
        'customer': {
          'phone': customer.isWalkIn ? null : customer.phone,
          'name': customer.name,
          'alternate_phone': customer.alternatePhone,
          'address': customer.address,
          'city': customer.city,
          'pincode': customer.pincode,
          'is_walk_in': customer.isWalkIn,
        },
        'student': {
          'name': customer.studentName,
          'class': customer.studentClass,
          'class_name': customer.className ?? customer.studentClass,
          'grade': customer.grade ?? customer.studentClass,
        },
        'items': items
            .map((i) => {
                  'product_id': i.product.id,
                  'variant_id': i.variant.id,
                  'product_name': i.product.name,
                  'variant_name': i.variant.name.startsWith('Size ')
                      ? i.variant.name
                      : 'Size ${i.variant.name}',
                  'size': i.variant.name,
                  'sku': i.variant.sku,
                  'school_id': i.product.schoolId,
                  'school_name': null,
                  'category': i.product.category,
                  'image_url': i.product.imageUrl,
                  'quantity': i.quantity,
                  'price': i.variant.price,
                  'unit_price': i.variant.price,
                  'line_total': i.lineTotal,
                  'name':
                      '${i.product.name} (${i.variant.name.startsWith('Size ') ? i.variant.name : 'Size ${i.variant.name}'})',
                  'title':
                      '${i.product.name} (${i.variant.name.startsWith('Size ') ? i.variant.name : 'Size ${i.variant.name}'})',
                  'display_name':
                      '${i.product.name} (${i.variant.name.startsWith('Size ') ? i.variant.name : 'Size ${i.variant.name}'})',
                  'product_snapshot': {
                    'product_name': i.product.name,
                    'variant_name': i.variant.name.startsWith('Size ')
                        ? i.variant.name
                        : 'Size ${i.variant.name}',
                    'size': i.variant.name,
                    'school_name': null,
                    'image_url': i.product.imageUrl,
                    'sku': i.variant.sku,
                  },
                })
            .toList(),
        'subtotal': subtotal,
        'discount': discountAmount,
        'total': total,
        'payment_method': paymentMethod.name,
        'payment_breakdown':
            resolvedPaymentBreakdown.map((entry) => entry.toJson()).toList(),
        'metadata': metadata,
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
