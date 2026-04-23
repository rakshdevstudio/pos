import 'cart_item.dart';

enum PaymentMethod { cash, upi, card, split }

enum OrderSyncStatus { pending, synced, failed }

class Order {
  final String offlineId;
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

  Map<String, dynamic> toJson() => {
        'offline_id': offlineId,
        'school_id': schoolId,
        'items': items.map((i) => i.toOrderLine()).toList(),
        'subtotal': subtotal,
        'discount_amount': discountAmount,
        'total': total,
        'payment_method': paymentMethod.name,
        'created_at': createdAt.toIso8601String(),
      };
}
