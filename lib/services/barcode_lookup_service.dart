import '../domain/models/models.dart';
import '../domain/repositories/product_repository.dart';

class BarcodeLookupService {
  final ProductRepository _productRepository;

  const BarcodeLookupService(this._productRepository);

  Future<ProductBarcodeMatch?> lookupVariantByBarcode(
    String code, {
    required String schoolId,
  }) async {
    final normalizedCode = normalizeBarcode(code);
    final normalizedSchoolId = schoolId.trim();
    if (normalizedCode == null || normalizedSchoolId.isEmpty) {
      return null;
    }

    return _productRepository.lookupProductByBarcode(
      schoolId: normalizedSchoolId,
      barcode: normalizedCode,
    );
  }

  String? normalizeBarcode(String code) {
    final normalized = code.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
