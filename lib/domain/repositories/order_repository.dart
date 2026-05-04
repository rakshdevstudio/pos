import '../models/models.dart';

abstract class OrderRepository {
  Future<int> saveOrderLocally(Order order);
  Future<int> deleteLocalOrder(String offlineId);
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
    List<PaymentAllocation> paymentBreakdown,
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
  });
  Future<bool> syncOrder(Order order);
  Future<List<Order>> getPendingOrders();
}
