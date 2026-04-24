import 'package:dio/dio.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/product_repository.dart';

class ProductRepositoryImpl implements ProductRepository {
  static const Duration _cacheTtl = Duration(seconds: 45);
  static const String _productsUrl =
      '${SupabaseConfig.url}/functions/v1/get-products';

  final Dio _dio;

  final Map<String, List<Product>> _productCache = {};
  final Map<String, DateTime> _cachedAt = {};
  final Map<String, Variant> _barcodeIndex = {};

  ProductRepositoryImpl({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                headers: const {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
              ),
            );

  @override
  Future<List<Product>> getProducts(String schoolId) async {
    final cached = _productCache[schoolId];
    final cachedAt = _cachedAt[schoolId];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return cached;
    }

    return fetchProducts(schoolId);
  }

  @override
  Future<List<Product>> fetchProducts(String schoolId) async {
    final response = await _dio.get(
      _productsUrl,
      queryParameters: {'school_id': schoolId},
    );

    final products = _extractProducts(response.data)
        .map((entry) => Product.fromJson(entry as Map<String, dynamic>))
        .toList();

    _setCache(schoolId, products);
    return products;
  }

  List<dynamic> _extractProducts(dynamic data) {
    if (data is List<dynamic>) return data;
    if (data is Map<String, dynamic>) {
      final products = data['products'];
      if (products is List<dynamic>) return products;
    }

    throw const FormatException('Unexpected products response');
  }

  void _setCache(String schoolId, List<Product> products) {
    _productCache[schoolId] = products;
    _cachedAt[schoolId] = DateTime.now();

    _barcodeIndex.clear();
    for (final product in products) {
      for (final v in product.variants) {
        final barcode = v.barcode;
        if (barcode != null && barcode.isNotEmpty) {
          _barcodeIndex[barcode.toUpperCase()] = v;
        }
      }
    }
  }

  @override
  List<Product> getCachedProducts(String schoolId) {
    return _productCache[schoolId] ?? [];
  }

  /// New required method
  Variant? getVariantByBarcode(String code) {
    return _barcodeIndex[code.toUpperCase()];
  }

  /// Backward compatible legacy method
  @override
  Variant? findVariantBySku(String sku) {
    return getVariantByBarcode(sku);
  }
}
