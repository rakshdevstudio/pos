import 'dart:convert';
import '../../domain/models/models.dart';
import '../../domain/repositories/product_repository.dart';
import '../local/database_helper.dart';
import '../remote/api_client.dart';

class ProductRepositoryImpl implements ProductRepository {
  static const Duration _cacheTtl = Duration(hours: 1);

  final ApiClient _apiClient;
  final DatabaseHelper _db;

  // In-memory mirrors for O(1) lookups — rebuilt from cache on restart
  final Map<int, List<Product>> _productCache = {};
  final Map<String, Variant> _skuIndex = {};

  ProductRepositoryImpl(this._apiClient, this._db);

  @override
  Future<List<Product>> getProducts(int schoolId) async {
    // 1. Serve from in-memory cache first (instant)
    if (_productCache.containsKey(schoolId)) {
      _backgroundRefresh(schoolId); // non-blocking
      return _productCache[schoolId]!;
    }

    // 2. Try SQLite cache
    final cached = await _getFromDb(schoolId);
    if (cached != null) {
      _productCache[schoolId] = cached;
      _buildSkuIndex(cached);
      _backgroundRefresh(schoolId); // non-blocking
      return cached;
    }

    // 3. Fetch from API (blocking only on first load)
    return _fetchFromApi(schoolId);
  }

  Future<List<Product>?> _getFromDb(int schoolId) async {
    final row = await _db.getProductsCache(schoolId);
    if (row == null) return null;

    // Check TTL
    final cachedAt = DateTime.tryParse(row['cached_at'] as String);
    if (cachedAt != null && DateTime.now().difference(cachedAt) > _cacheTtl) {
      return null; // stale — force API refresh
    }

    try {
      final list = jsonDecode(row['products_json'] as String) as List<dynamic>;
      return list.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<Product>> _fetchFromApi(int schoolId) async {
    try {
      final baseUrl = ApiClient.baseUrl;
      final response = await _apiClient.dio.get(
        '$baseUrl/products',
        queryParameters: {'school_id': schoolId},
      );
      final data = response.data as List<dynamic>;
      final products =
          data.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
      await _persistToDb(schoolId, products);
      return products;
    } catch (_) {
      // API failed — return mock data for offline dev
      return _mockProducts(schoolId);
    }
  }

  void _backgroundRefresh(int schoolId) {
    Future.microtask(() async {
      try {
        final baseUrl = ApiClient.baseUrl;
        final response = await _apiClient.dio.get(
          '$baseUrl/products',
          queryParameters: {'school_id': schoolId},
        );
        final data = response.data as List<dynamic>;
        final products =
            data.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
        await _persistToDb(schoolId, products);
      } catch (_) {
        // Silent — stale cache is fine
      }
    });
  }

  Future<void> _persistToDb(int schoolId, List<Product> products) async {
    _productCache[schoolId] = products;
    _buildSkuIndex(products);
    final json = jsonEncode(products.map((p) => p.toJson()).toList());
    await _db.cacheProducts(schoolId, json);
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

  @override
  Future<void> cacheProducts(int schoolId, List<Product> products) async {
    await _persistToDb(schoolId, products);
  }

  @override
  List<Product> getCachedProducts(int schoolId) {
    return _productCache[schoolId] ?? [];
  }

  @override
  Variant? findVariantBySku(String sku) {
    return _skuIndex[sku.toUpperCase()];
  }

  Future<void> loadCache(int schoolId) async {
    final cached = await _getFromDb(schoolId);
    if (cached != null) {
      _productCache[schoolId] = cached;
      _buildSkuIndex(cached);
    }
  }

  // ── Mock fallback ─────────────────────────────────────────────────────────

  List<Product> _mockProducts(int schoolId) {
    final products = [
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
    // Cache mock data so the next load is instant
    _persistToDb(schoolId, products);
    return products;
  }
}
