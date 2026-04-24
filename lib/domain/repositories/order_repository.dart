import '../models/models.dart';

abstract class OrderRepository {
  Future<int> saveOrderLocally(Order order);
  Future<void> applyInventoryMovements({
    required List<CartItem> items,
    required String branchId,
  });
  Future<bool> syncOrder(Order order);
  Future<List<Order>> getPendingOrders();
}
