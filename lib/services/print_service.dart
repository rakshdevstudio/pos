import '../domain/models/models.dart';

abstract class PrintService {
  Future<bool> printReceipt(Order order);
  Future<bool> isAvailable();
}

/// Mock implementation — will be replaced by thermal printer SDK
class MockPrintService implements PrintService {
  @override
  Future<bool> printReceipt(Order order) async {
    // Simulate print delay
    await Future.delayed(const Duration(milliseconds: 800));
    // In production: connect to thermal printer via Bluetooth/USB
    return true;
  }

  @override
  Future<bool> isAvailable() async => true;
}

final printService = MockPrintService();
