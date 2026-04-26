import '../models/models.dart';

abstract class OrderRepository {
  Future<int> saveOrderLocally(Order order);
  Future<int> deleteLocalOrder(String offlineId);
  Future<void> applyInventoryMovements({
    required List<CartItem> items,
    required String branchId,
    required String schoolId,
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    String? orderId,
  });
  Future<bool> syncOrder(Order order);
  Future<List<Order>> getPendingOrders();
}
