import '../models/models.dart';

abstract class ProductRepository {
  Future<List<Product>> fetchProducts({
    required String schoolId,
    String? classId,
    String? gender,
  });
  Future<List<Product>> getProducts({
    required String schoolId,
    String? classId,
    String? gender,
  });
  List<Product> getCachedProducts({
    required String schoolId,
    String? classId,
    String? gender,
  });
  Future<ProductBarcodeMatch?> lookupProductByBarcode({
    required String schoolId,
    required String barcode,
  });
  void clearCache();
  Variant? findVariantBySku(String sku);
}
