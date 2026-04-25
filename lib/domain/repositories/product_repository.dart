import '../models/models.dart';

abstract class ProductRepository {
  Future<List<Product>> fetchProducts(String schoolId);
  Future<List<Product>> getProducts(String schoolId);
  List<Product> getCachedProducts(String schoolId);
  void clearCache();
  Variant? findVariantBySku(String sku);
}
