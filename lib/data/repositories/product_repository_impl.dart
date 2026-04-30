import 'package:flutter/foundation.dart';
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
  static const String _productSelectFields =
      'id,name,school_id,class_id,gender,category,image_url,description,is_active,created_at';

  final Dio _dio;

  final Map<String, List<Product>> _productCache = {};
  final Map<String, DateTime> _cachedAt = {};
  final Map<String, ProductBarcodeMatch> _barcodeMatchCache = {};
  final Map<String, Variant> _legacyBarcodeIndex = {};
  _VariantSchemaProfile? _variantSchemaProfile;

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
  Future<List<Product>> getProducts({
    required String schoolId,
    String? classId,
    String? gender,
  }) async {
    final key = _cacheKey(
      schoolId: schoolId,
      classId: classId,
      gender: gender,
    );
    final cached = _productCache[key];
    final cachedAt = _cachedAt[key];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return cached;
    }

    return fetchProducts(
      schoolId: schoolId,
      classId: classId,
      gender: gender,
    );
  }

  @override
  Future<List<Product>> fetchProducts({
    required String schoolId,
    String? classId,
    String? gender,
  }) async {
    final scopedSchoolId = schoolId.trim();
    final scopedClassId = classId?.trim();
    final normalizedGender = _normalizeGenderFilter(gender);

    if (scopedSchoolId.isEmpty) {
      return const [];
    }

    if (scopedClassId != null && scopedClassId.isNotEmpty) {
      final filteredProducts = await _fetchProductsFromRest(
        schoolId: scopedSchoolId,
        classId: scopedClassId,
        gender: normalizedGender,
      );
      _setCache(
        schoolId: scopedSchoolId,
        classId: scopedClassId,
        gender: normalizedGender,
        products: filteredProducts,
      );
      return filteredProducts;
    }

    return _fetchAllSchoolProducts(scopedSchoolId);
  }

  List<dynamic> _extractProducts(dynamic data) {
    if (data is List<dynamic>) return data;
    if (data is Map<String, dynamic>) {
      final products = data['products'];
      if (products is List<dynamic>) return products;
    }

    throw const FormatException('Unexpected products response');
  }

  Future<List<Product>> _fetchAllSchoolProducts(String schoolId) async {
    try {
      final response = await _dio.get(
        _productsUrl,
        queryParameters: {'school_id': schoolId},
      );

      final products = _parseProducts(response.data, schoolId);
      if (products.isEmpty) {
        final fallbackProducts = await _fetchProductsFromRest(
          schoolId: schoolId,
        );
        if (fallbackProducts.isNotEmpty) {
          _setCache(schoolId: schoolId, products: fallbackProducts);
          return fallbackProducts;
        }
      }

      _setCache(schoolId: schoolId, products: products);
      return products;
    } on DioException catch (error) {
      debugPrint(
        'Edge function failed for school_id $schoolId: ${error.response?.statusCode}',
      );
      final fallbackProducts = await _fetchProductsFromRest(schoolId: schoolId);
      _setCache(schoolId: schoolId, products: fallbackProducts);
      return fallbackProducts;
    }
  }

  void _setCache({
    required String schoolId,
    String? classId,
    String? gender,
    required List<Product> products,
  }) {
    final cacheKey = _cacheKey(
      schoolId: schoolId,
      classId: classId,
      gender: gender,
    );
    _productCache[cacheKey] = products;
    _cachedAt[cacheKey] = DateTime.now();

    for (final product in products) {
      for (final v in product.variants) {
        _cacheVariantLookup(
          schoolId: schoolId,
          product: product,
          variant: v,
        );
      }
    }
  }

  @override
  List<Product> getCachedProducts({
    required String schoolId,
    String? classId,
    String? gender,
  }) {
    return _productCache[_cacheKey(
          schoolId: schoolId,
          classId: classId,
          gender: gender,
        )] ??
        const [];
  }

  @override
  void clearCache() {
    _productCache.clear();
    _cachedAt.clear();
    _barcodeMatchCache.clear();
    _legacyBarcodeIndex.clear();
    _variantSchemaProfile = null;
  }

  @override
  Future<ProductBarcodeMatch?> lookupProductByBarcode({
    required String schoolId,
    required String barcode,
  }) async {
    final scopedSchoolId = schoolId.trim();
    final normalizedBarcode = _normalizeCode(barcode);
    if (scopedSchoolId.isEmpty || normalizedBarcode == null) {
      return null;
    }

    final cached =
        _barcodeMatchCache[_barcodeKey(scopedSchoolId, normalizedBarcode)];
    if (cached != null) {
      return cached;
    }

    for (final candidate in _barcodeCandidates(barcode)) {
      final remoteMatch = await _fetchProductByBarcodeFromRest(
        schoolId: scopedSchoolId,
        barcode: candidate,
      );
      if (remoteMatch == null) {
        continue;
      }

      _cacheVariantLookup(
        schoolId: scopedSchoolId,
        product: remoteMatch.product,
        variant: remoteMatch.variant,
      );
      _barcodeMatchCache[_barcodeKey(scopedSchoolId, normalizedBarcode)] =
          remoteMatch;
      return remoteMatch;
    }

    return null;
  }

  /// Backward compatible legacy method
  @override
  Variant? findVariantBySku(String sku) {
    return _legacyBarcodeIndex[sku.trim().toUpperCase()];
  }

  List<Product> _parseProducts(dynamic data, String _) {
    return _extractProducts(data)
        .map((entry) => Product.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  Future<List<Product>> _fetchProductsFromRest({
    required String schoolId,
    String? classId,
    String? gender,
  }) async {
    final variantSchema = await _getVariantSchemaProfile();
    final prefs = await SharedPreferences.getInstance();
    final branchId = prefs.getString('selectedBranchId')?.trim();
    final queryParameters = <String, dynamic>{
      'select': '$_productSelectFields,${variantSchema.nestedProductSelect}',
      'school_id': 'eq.$schoolId',
      'is_active': 'eq.true',
      'archived': 'eq.false',
      'deleted_at': 'is.null',
      'order': 'name.asc',
      if (classId != null && classId.isNotEmpty) 'class_id': 'eq.$classId',
    };
    _applyGenderQuery(queryParameters, gender);

    final productsResponse = await _dio.get(
      '$_restUrl/products',
      queryParameters: queryParameters,
      options: Options(headers: _restHeaders),
    );

    final productRows =
        (productsResponse.data as List<dynamic>).cast<Map<String, dynamic>>();
    if (productRows.isEmpty) {
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
              'class_id': row['class_id'],
              'gender': row['gender'],
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
                  'barcode': variantRow['barcode'],
                  'barcode_value': variantRow['barcode_value'],
                  'price': priceValue,
                  'stock': stockValue,
                  'is_active': _boolToFlag(variantRow['is_active']),
                };
              }).toList()),
            }))
        .toList();
    return fallbackProducts;
  }

  Future<ProductBarcodeMatch?> _fetchProductByBarcodeFromRest({
    required String schoolId,
    required String barcode,
  }) async {
    final variantSchema = await _getVariantSchemaProfile();
    final prefs = await SharedPreferences.getInstance();
    final branchId = prefs.getString('selectedBranchId')?.trim();

    Map<String, dynamic>? row;
    for (final field in variantSchema.lookupFields) {
      final response = await _dio.get(
        '$_restUrl/product_variants',
        queryParameters: {
          'select':
              variantSchema.variantSelectWithProduct(_productSelectFields),
          field: 'eq.$barcode',
          'products.school_id': 'eq.$schoolId',
          'products.is_active': 'eq.true',
          'products.archived': 'eq.false',
          'products.deleted_at': 'is.null',
          'limit': 1,
        },
        options: Options(headers: _restHeaders),
      );

      final rows =
          (response.data as List<dynamic>).cast<Map<String, dynamic>>();
      if (rows.isNotEmpty) {
        row = rows.first;
        break;
      }
    }

    if (row == null) {
      return null;
    }

    final productRow = row['products'];
    if (productRow is! Map<String, dynamic>) {
      return null;
    }

    var stockValue = _asInt(row['stock']);
    final variantId = row['id']?.toString() ?? '';
    if (branchId != null && branchId.isNotEmpty && variantId.isNotEmpty) {
      final inventoryResponse = await _dio.get(
        '$_restUrl/branch_inventory',
        queryParameters: {
          'select': 'variant_id,stock',
          'branch_id': 'eq.$branchId',
          'variant_id': 'eq.$variantId',
          'limit': 1,
        },
        options: Options(headers: _restHeaders),
      );
      final inventoryRows = (inventoryResponse.data as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (inventoryRows.isNotEmpty) {
        stockValue = _asInt(inventoryRows.first['stock']);
      }
    }

    final product = Product.fromJson({
      'id': productRow['id'],
      'school_id': productRow['school_id'],
      'class_id': productRow['class_id'],
      'gender': productRow['gender'],
      'name': productRow['name'],
      'description': productRow['description'],
      'image_url': productRow['image_url'],
      'category': productRow['category'],
      'is_active': _boolToFlag(productRow['is_active']),
      'updated_at': productRow['created_at'],
      'variants': [
        {
          'id': row['id'],
          'product_id': row['product_id'],
          'size': row['size'],
          'name': row['size'],
          'sku': row['sku'],
          'barcode': row['barcode'],
          'barcode_value': row['barcode_value'],
          'price': row['price_override'] ?? row['base_price'] ?? 0,
          'stock': stockValue,
          'is_active': _boolToFlag(row['is_active']),
        },
      ],
    });

    if (product.variants.isEmpty) {
      return null;
    }

    return ProductBarcodeMatch(
      product: product,
      variant: product.variants.first,
    );
  }

  Map<String, String> get _restHeaders => {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      };

  Future<_VariantSchemaProfile> _getVariantSchemaProfile() async {
    final cachedProfile = _variantSchemaProfile;
    if (cachedProfile != null) {
      return cachedProfile;
    }

    for (final profile in _variantSchemaProfiles) {
      try {
        await _dio.get(
          '$_restUrl/product_variants',
          queryParameters: {
            'select': profile.variantSelect,
            'limit': 1,
          },
          options: Options(headers: _restHeaders),
        );
        _variantSchemaProfile = profile;
        return profile;
      } on DioException catch (error) {
        if (error.response?.statusCode == 400) {
          continue;
        }
        rethrow;
      }
    }

    _variantSchemaProfile = _variantSchemaProfiles.last;
    return _variantSchemaProfile!;
  }

  void _cacheVariantLookup({
    required String schoolId,
    required Product product,
    required Variant variant,
  }) {
    final match = ProductBarcodeMatch(product: product, variant: variant);
    final values = <String?>{
      variant.barcode,
      variant.sku,
    };

    for (final value in values) {
      final normalizedValue = _normalizeCode(value);
      if (normalizedValue == null) {
        continue;
      }

      _legacyBarcodeIndex[normalizedValue] = variant;
      _barcodeMatchCache[_barcodeKey(schoolId, normalizedValue)] = match;
    }
  }

  Iterable<String> _barcodeCandidates(String barcode) sync* {
    final trimmed = barcode.trim();
    final normalized = _normalizeCode(barcode);
    final yielded = <String>{};
    if (trimmed.isNotEmpty && yielded.add(trimmed)) {
      yield trimmed;
    }
    if (normalized != null && yielded.add(normalized)) {
      yield normalized;
    }
  }

  void _applyGenderQuery(
    Map<String, dynamic> queryParameters,
    String? gender,
  ) {
    final normalizedGender = _normalizeGenderFilter(gender);
    if (normalizedGender == null) return;

    switch (normalizedGender) {
      case 'Male':
        queryParameters['gender'] = 'in.(Male,Boys)';
        return;
      case 'Female':
        queryParameters['gender'] = 'in.(Female,Girls)';
        return;
      default:
        queryParameters['gender'] = 'eq.$normalizedGender';
    }
  }

  String _cacheKey({
    required String schoolId,
    String? classId,
    String? gender,
  }) {
    final normalizedSchoolId = schoolId.trim();
    final normalizedClassId = classId?.trim() ?? '';
    final normalizedGender = _normalizeGenderFilter(gender) ?? '';
    return '$normalizedSchoolId|$normalizedClassId|$normalizedGender';
  }

  String _barcodeKey(String schoolId, String barcode) {
    return '${schoolId.trim()}|${_normalizeCode(barcode) ?? ''}';
  }

  String? _normalizeCode(String? code) {
    final trimmed = code?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed.toUpperCase();
  }

  String? _normalizeGenderFilter(String? gender) {
    final normalized = gender?.trim();
    if (normalized == null || normalized.isEmpty) return null;

    switch (normalized.toLowerCase()) {
      case 'all':
        return null;
      case 'boys':
      case 'male':
        return 'Male';
      case 'girls':
      case 'female':
        return 'Female';
      case 'unisex':
        return 'Unisex';
      default:
        return normalized;
    }
  }

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

class _VariantSchemaProfile {
  final List<String> variantFields;
  final List<String> lookupFields;

  const _VariantSchemaProfile({
    required this.variantFields,
    required this.lookupFields,
  });

  String get variantSelect => variantFields.join(',');

  String get nestedProductSelect => 'product_variants($variantSelect)';

  String variantSelectWithProduct(String productFields) {
    return '$variantSelect,products!inner($productFields)';
  }
}

const List<_VariantSchemaProfile> _variantSchemaProfiles = [
  _VariantSchemaProfile(
    variantFields: [
      'id',
      'product_id',
      'size',
      'sku',
      'barcode',
      'barcode_value',
      'stock',
      'price_override',
      'base_price',
      'is_active',
    ],
    lookupFields: ['barcode', 'barcode_value', 'sku'],
  ),
  _VariantSchemaProfile(
    variantFields: [
      'id',
      'product_id',
      'size',
      'sku',
      'barcode_value',
      'stock',
      'price_override',
      'base_price',
      'is_active',
    ],
    lookupFields: ['barcode_value', 'sku'],
  ),
  _VariantSchemaProfile(
    variantFields: [
      'id',
      'product_id',
      'size',
      'sku',
      'barcode',
      'stock',
      'price_override',
      'base_price',
      'is_active',
    ],
    lookupFields: ['barcode', 'sku'],
  ),
  _VariantSchemaProfile(
    variantFields: [
      'id',
      'product_id',
      'size',
      'sku',
      'stock',
      'price_override',
      'base_price',
      'is_active',
    ],
    lookupFields: ['sku'],
  ),
];
