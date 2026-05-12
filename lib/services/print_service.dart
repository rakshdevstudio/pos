import '../domain/models/models.dart';

abstract class PrintService {
  Future<bool> printReceipt(Order order);
  Future<bool> isAvailable();
}

/// Receipt data structure with ILLUME branding
class ReceiptData {
  final Order order;
  final String schoolName;
  final String? schoolLogoPath;
  final bool includeIllumeLogo;

  ReceiptData({
    required this.order,
    required this.schoolName,
    this.schoolLogoPath,
    this.includeIllumeLogo = true,
  });
}

/// Mock implementation — will be replaced by thermal printer SDK
///
/// Features:
/// - Monochrome ILLUME logo (black) for thermal printers
/// - QR code generation for order tracking
/// - Optimized 80mm thermal printer formatting
/// - Zero gradients for reliable thermal printing
class MockPrintService implements PrintService {
  @override
  Future<bool> printReceipt(Order order) async {
    // Simulate print delay
    await Future.delayed(const Duration(milliseconds: 800));

    // In production: connect to thermal printer via Bluetooth/USB
    // Use ReceiptData to structure receipt layout with:
    // - Monochrome ILLUME logo (assets/icons/illume_logo_monochrome.svg)
    // - School name and address
    // - Order details
    // - QR code
    // - Footer with branding

    return true;
  }

  @override
  Future<bool> isAvailable() async => true;

  /// Format receipt layout for 80mm thermal printer
  String _formatReceipt(ReceiptData data) {
    final buffer = StringBuffer();

    // Monochrome ILLUME logo
    buffer.writeln('═' * 40);
    buffer.writeln('  ILLUME POS - Receipt');
    buffer.writeln('═' * 40);

    // School and order info
    buffer.writeln('\nStore: ${data.schoolName}');
    buffer.writeln('Order: ${data.order.offlineId}');
    buffer.writeln('Date: ${DateTime.now().toString()}');

    // Items
    buffer.writeln('\n' + '─' * 40);
    for (final item in data.order.items) {
      buffer.writeln('${item.product.name} x${item.quantity}');
      buffer.writeln('₹${item.lineTotal}');
    }

    // Totals
    buffer.writeln('─' * 40);
    buffer.writeln('Total: ₹${data.order.total}');
    buffer.writeln('\n' + '═' * 40);
    buffer.writeln('  Thank you - ILLUME');
    buffer.writeln('═' * 40);

    return buffer.toString();
  }
}

final printService = MockPrintService();
