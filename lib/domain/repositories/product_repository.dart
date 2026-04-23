import '../models/models.dart';

abstract class ProductRepository {
  Future<List<Product>> getProducts(int schoolId);
  Future<void> cacheProducts(int schoolId, List<Product> products);
  List<Product> getCachedProducts(int schoolId);
  Variant? findVariantBySku(String sku);
}
