import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/supabase_config.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/product_repository.dart';

class ProductRepositoryImpl implements ProductRepository {
  static const Duration _cacheTtl = Duration(seconds: 45);
  static const String _productsUrl =
      '${SupabaseConfig.url}/functions/v1/get-products';
  static const String _restUrl = '${SupabaseConfig.url}/rest/v1';

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
    final scopedSchoolId = schoolId.trim();
    print("API CALL → school_id: $schoolId");
    print("FULL URL:");
    print(
      "https://rkbkorssqydpetilwltc.supabase.co/functions/v1/get-products?school_id=$scopedSchoolId",
    );
    if (scopedSchoolId.length < 30) {
      print("❌ INVALID SCHOOL ID (NOT UUID): $schoolId");
    }
    try {
      final response = await _dio.get(
        _productsUrl,
        queryParameters: {'school_id': scopedSchoolId},
      );

      final products = _parseProducts(response.data, scopedSchoolId);
      if (scopedSchoolId.isNotEmpty && products.isEmpty) {
        final fallbackProducts = await _fetchProductsFromRest(scopedSchoolId);
        if (fallbackProducts.isNotEmpty) {
          _setCache(scopedSchoolId, fallbackProducts);
          return fallbackProducts;
        }
      }

      _setCache(scopedSchoolId, products);
      return products;
    } on DioException catch (error) {
      print(
        'Edge function failed for school_id $scopedSchoolId: ${error.response?.statusCode}',
      );
      final fallbackProducts = await _fetchProductsFromRest(scopedSchoolId);
      _setCache(scopedSchoolId, fallbackProducts);
      return fallbackProducts;
    }
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

  @override
  void clearCache() {
    _productCache.clear();
    _cachedAt.clear();
    _barcodeIndex.clear();
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

  List<Product> _parseProducts(dynamic data, String scopedSchoolId) {
    final products = _extractProducts(data)
        .map((entry) => Product.fromJson(entry as Map<String, dynamic>))
        .toList();
    print("API RESPONSE LENGTH: ${products.length}");
    print(
      "FIRST PRODUCT: ${products.isNotEmpty ? products[0].name : "EMPTY"}",
    );

    final mismatched = products
        .where((product) =>
            product.schoolId.isNotEmpty && product.schoolId != scopedSchoolId)
        .length;
    if (mismatched > 0) {
      print(
          'Warning: $mismatched products have school_id different from request');
    }

    return products;
  }

  Future<List<Product>> _fetchProductsFromRest(String schoolId) async {
    print("REST FALLBACK → school_id: $schoolId");
    final prefs = await SharedPreferences.getInstance();
    final branchId = prefs.getString('selectedBranchId')?.trim();
    final productsResponse = await _dio.get(
      '$_restUrl/products',
      queryParameters: {
        'select':
            'id,name,school_id,category,image_url,description,is_active,created_at,product_variants(id,product_id,size,sku,stock,price_override,base_price,is_active)',
        if (schoolId.isNotEmpty) 'school_id': 'eq.$schoolId',
        'order': 'name.asc',
      },
      options: Options(headers: _restHeaders),
    );

    final productRows =
        (productsResponse.data as List<dynamic>).cast<Map<String, dynamic>>();
    if (productRows.isEmpty) {
      print("REST FALLBACK COUNT: 0");
      return const [];
    }

    final inventoryByVariantId = <String, int>{};
    if (branchId != null && branchId.isNotEmpty) {
      final inventoryResponse = await _dio.get(
        '$_restUrl/branch_inventory',
        queryParameters: {
          'select': 'variant_id,stock',
          'branch_id': 'eq.$branchId',
        },
        options: Options(headers: _restHeaders),
      );
      final inventoryRows = (inventoryResponse.data as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final row in inventoryRows) {
        final variantId = row['variant_id']?.toString();
        if (variantId == null || variantId.isEmpty) continue;
        inventoryByVariantId[variantId] = _asInt(row['stock']);
      }
    }

    final fallbackProducts = productRows
        .map((row) => Product.fromJson({
              'id': row['id'],
              'school_id': row['school_id'],
              'name': row['name'],
              'description': row['description'],
              'image_url': row['image_url'],
              'category': row['category'],
              'is_active': _boolToFlag(row['is_active']),
              'updated_at': row['created_at'],
              'variants': ((row['product_variants'] as List<dynamic>? ??
                      const <dynamic>[])
                  .cast<Map<String, dynamic>>()
                  .map((variantRow) {
                final variantId = variantRow['id']?.toString() ?? '';
                final priceValue = variantRow['price_override'] ??
                    variantRow['base_price'] ??
                    0;
                final stockValue = inventoryByVariantId[variantId] ??
                    _asInt(variantRow['stock']);
                return {
                  'id': variantId,
                  'product_id': variantRow['product_id'],
                  'size': variantRow['size'],
                  'name': variantRow['size'],
                  'sku': variantRow['sku'],
                  'barcode': variantRow['sku'],
                  'price': priceValue,
                  'stock': stockValue,
                  'is_active': _boolToFlag(variantRow['is_active']),
                };
              }).toList()),
            }))
        .toList();
    print("REST FALLBACK COUNT: ${fallbackProducts.length}");
    print(
      "REST FALLBACK FIRST PRODUCT: ${fallbackProducts.isNotEmpty ? fallbackProducts[0].name : "EMPTY"}",
    );
    return fallbackProducts;
  }

  Map<String, String> get _restHeaders => {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      };

  static int _boolToFlag(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    return _asInt(value ?? 1);
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
