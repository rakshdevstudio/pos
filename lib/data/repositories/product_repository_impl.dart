import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/product_repository.dart';
import '../remote/api_client.dart';

class ProductRepositoryImpl implements ProductRepository {
  static const String _cachePrefix = 'products_cache_';
  final ApiClient _apiClient;

  // In-memory variant lookup map: sku -> Variant
  final Map<String, Variant> _skuIndex = {};
  final Map<int, List<Product>> _productCache = {};

  ProductRepositoryImpl(this._apiClient);

  @override
  Future<List<Product>> getProducts(int schoolId) async {
    try {
      final baseUrl = await ApiClient.getBaseUrl();
      final response = await _apiClient.dio.get(
        '$baseUrl/products',
        queryParameters: {'school_id': schoolId},
      );
      final data = response.data as List<dynamic>;
      final products = data
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
      await cacheProducts(schoolId, products);
      _buildSkuIndex(products);
      return products;
    } catch (_) {
      final cached = getCachedProducts(schoolId);
      if (cached.isNotEmpty) return cached;

      final mockProducts = [
        Product(
          id: 1,
          schoolId: schoolId,
          name: 'Classic White Shirt - Half Sleeves',
          category: 'Shirts',
          variants: [
            Variant(id: 101, productId: 1, size: 'M', price: 650, sku: 'WHT-S-M'),
            Variant(id: 102, productId: 1, size: 'L', price: 650, sku: 'WHT-S-L'),
          ],
        ),
        Product(
          id: 2,
          schoolId: schoolId,
          name: 'Navy Blue Trousers',
          category: 'Bottoms',
          variants: [
            Variant(id: 201, productId: 2, size: '28', price: 850, sku: 'NAV-T-28'),
            Variant(id: 202, productId: 2, size: '30', price: 850, sku: 'NAV-T-30'),
            Variant(id: 203, productId: 2, size: '32', price: 900, sku: 'NAV-T-32'),
          ],
        ),
        Product(
          id: 3,
          schoolId: schoolId,
          name: 'School Tie - Standard',
          category: 'Accessories',
          variants: [
            Variant(id: 301, productId: 3, size: 'Free', price: 150, sku: 'TIE-STD'),
          ],
        ),
      ];
      await cacheProducts(schoolId, mockProducts);
      return mockProducts;
    }
  }

  @override
  Future<void> cacheProducts(int schoolId, List<Product> products) async {
    _productCache[schoolId] = products;
    _buildSkuIndex(products);
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(products.map((p) => p.toJson()).toList());
    await prefs.setString('$_cachePrefix$schoolId', json);
  }

  @override
  List<Product> getCachedProducts(int schoolId) {
    return _productCache[schoolId] ?? [];
  }

  @override
  Variant? findVariantBySku(String sku) {
    return _skuIndex[sku.toUpperCase()];
  }

  void _buildSkuIndex(List<Product> products) {
    for (final product in products) {
      for (final variant in product.variants) {
        if (variant.sku != null) {
          _skuIndex[variant.sku!.toUpperCase()] = variant;
        }
      }
    }
  }

  Future<void> loadCache(int schoolId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cachePrefix$schoolId');
    if (raw != null) {
      final list = jsonDecode(raw) as List<dynamic>;
      final products = list
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
      _productCache[schoolId] = products;
      _buildSkuIndex(products);
    }
  }
}
