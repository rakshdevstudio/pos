import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/domain/models/models.dart';
import 'package:pos_app/domain/repositories/product_repository.dart';
import 'package:pos_app/services/barcode_lookup_service.dart';
import 'package:pos_app/services/cart_service.dart';

void main() {
  group('Variant.fromJson', () {
    test('keeps sku separate from barcode_value', () {
      final variant = Variant.fromJson({
        'id': 'variant-1',
        'product_id': 'product-1',
        'size': '32',
        'sku': 'SKU-32',
        'barcode_value': 'ILL-00001000',
        'price': 440,
        'stock': 3,
      });

      expect(variant.sku, 'SKU-32');
      expect(variant.barcode, 'ILL-00001000');
      expect(variant.size, '32');
    });
  });

  group('BarcodeLookupService', () {
    test('trims barcode input before repository lookup', () async {
      final repository = _FakeProductRepository();
      final service = BarcodeLookupService(repository);
      final match = _sampleMatch();
      repository.response = match;

      final result = await service.lookupVariantByBarcode(
        '  ILL-00001000 \n',
        schoolId: ' school-1 ',
      );

      expect(result, same(match));
      expect(repository.lastSchoolId, 'school-1');
      expect(repository.lastBarcode, 'ILL-00001000');
    });

    test('returns null for blank barcode input', () async {
      final repository = _FakeProductRepository();
      final service = BarcodeLookupService(repository);

      final result = await service.lookupVariantByBarcode(
        '   \n',
        schoolId: 'school-1',
      );

      expect(result, isNull);
      expect(repository.lastBarcode, isNull);
    });
  });

  group('CartNotifier barcode adds', () {
    test('increments quantity and blocks overflow at stock limit', () {
      final notifier = CartNotifier();
      final match = _sampleMatch(stock: 2);

      expect(
        notifier.addItemWithResult(match.product, match.variant),
        CartAddResult.added,
      );
      expect(notifier.state.items.single.quantity, 1);

      expect(
        notifier.addItemWithResult(match.product, match.variant),
        CartAddResult.added,
      );
      expect(notifier.state.items.single.quantity, 2);

      expect(
        notifier.addItemWithResult(match.product, match.variant),
        CartAddResult.stockLimitReached,
      );
      expect(notifier.state.items.single.quantity, 2);
    });

    test('rejects out of stock barcode adds', () {
      final notifier = CartNotifier();
      final match = _sampleMatch(stock: 0);

      expect(
        notifier.addItemWithResult(match.product, match.variant),
        CartAddResult.outOfStock,
      );
      expect(notifier.state.items, isEmpty);
    });
  });
}

ProductBarcodeMatch _sampleMatch({int stock = 5}) {
  final variant = Variant(
    id: 'variant-1',
    productId: 'product-1',
    name: '32',
    sku: 'SKU-32',
    barcode: 'ILL-00001000',
    price: 440,
    stock: stock,
  );
  final product = Product(
    id: 'product-1',
    schoolId: 'school-1',
    classId: 'class-1',
    gender: 'Girls',
    name: 'Beige Skirt',
    imageUrl: 'https://example.com/skirt.png',
    category: 'Bottomwear',
    variants: [variant],
  );

  return ProductBarcodeMatch(product: product, variant: variant);
}

class _FakeProductRepository implements ProductRepository {
  String? lastSchoolId;
  String? lastBarcode;
  ProductBarcodeMatch? response;

  @override
  void clearCache() {}

  @override
  Future<List<Product>> fetchProducts({
    required String schoolId,
    String? classId,
    String? gender,
  }) async {
    return const [];
  }

  @override
  Variant? findVariantBySku(String sku) {
    return null;
  }

  @override
  List<Product> getCachedProducts({
    required String schoolId,
    String? classId,
    String? gender,
  }) {
    return const [];
  }

  @override
  Future<List<Product>> getProducts({
    required String schoolId,
    String? classId,
    String? gender,
  }) async {
    return const [];
  }

  @override
  Future<ProductBarcodeMatch?> lookupProductByBarcode({
    required String schoolId,
    required String barcode,
  }) async {
    lastSchoolId = schoolId;
    lastBarcode = barcode;
    return response;
  }
}
