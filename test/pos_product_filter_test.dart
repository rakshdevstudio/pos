import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/data/repositories/pos_product_filter.dart';
import 'package:pos_app/domain/models/product.dart';
import 'package:pos_app/domain/models/variant.dart';

void main() {
  group('Product parsing', () {
    test('collects class ids from product and variant payloads', () {
      final product = Product.fromJson({
        'id': 'product-1',
        'school_id': 'school-1',
        'class_id': 'class-legacy',
        'class_ids': ['class-1', 'class-2'],
        'name': 'Shirt',
        'is_active': true,
        'variants': [
          {
            'id': 'variant-1',
            'product_id': 'product-1',
            'size': '32',
            'price': 499,
            'stock': 4,
            'class_ids': ['class-3'],
            'is_active': true,
          },
        ],
      });

      expect(
        product.classIds,
        containsAll(<String>['class-legacy', 'class-1', 'class-2']),
      );
      expect(product.variants.single.classIds, contains('class-3'));
    });
  });

  group('PosProductFilter', () {
    final schoolWideProducts = <Product>[
      const Product(
        id: 'product-1',
        schoolId: 'school-1',
        classIds: ['class-1', 'class-2'],
        gender: 'Boys',
        name: 'Multi Class Shirt',
        isActive: 1,
        variants: [
          Variant(
            id: 'variant-1',
            productId: 'product-1',
            name: '32',
            price: 499,
            stock: 5,
            isActive: 1,
          ),
        ],
      ),
      const Product(
        id: 'product-2',
        schoolId: 'school-1',
        gender: 'Unisex',
        name: 'Tie',
        isActive: 1,
        variants: [
          Variant(
            id: 'variant-2',
            productId: 'product-2',
            name: 'Free Size',
            price: 199,
            stock: 10,
            classIds: ['class-1'],
            isActive: 1,
          ),
        ],
      ),
      const Product(
        id: 'product-3',
        schoolId: 'school-1',
        gender: null,
        name: 'Socks',
        isActive: 1,
        variants: [
          Variant(
            id: 'variant-3',
            productId: 'product-3',
            name: 'M',
            price: 99,
            stock: 8,
            classIds: ['class-1'],
            isActive: 1,
          ),
        ],
      ),
      const Product(
        id: 'product-4',
        schoolId: 'school-1',
        classIds: ['class-1'],
        gender: 'Girls',
        name: 'Girls Skirt',
        isActive: 1,
        variants: [
          Variant(
            id: 'variant-4',
            productId: 'product-4',
            name: '30',
            price: 549,
            stock: 6,
            isActive: 1,
          ),
        ],
      ),
      const Product(
        id: 'product-5',
        schoolId: 'school-2',
        classIds: ['class-1'],
        gender: 'Boys',
        name: 'Other School Item',
        isActive: 1,
        variants: [
          Variant(
            id: 'variant-5',
            productId: 'product-5',
            name: '34',
            price: 449,
            stock: 6,
            isActive: 1,
          ),
        ],
      ),
    ];

    test('shows multi-class products when either class is selected', () {
      final classOne = PosProductFilter.apply(
        products: schoolWideProducts,
        schoolId: 'school-1',
        classId: 'class-1',
      );
      final classTwo = PosProductFilter.apply(
        products: schoolWideProducts,
        schoolId: 'school-1',
        classId: 'class-2',
      );

      expect(classOne.products.map((product) => product.id),
          contains('product-1'));
      expect(classTwo.products.map((product) => product.id),
          contains('product-1'));
      expect(classOne.products.map((product) => product.id),
          isNot(contains('product-5')));
    });

    test('keeps unisex and missing-gender products in boys and girls views',
        () {
      final boys = PosProductFilter.apply(
        products: schoolWideProducts,
        schoolId: 'school-1',
        classId: 'class-1',
        gender: 'Boys',
      );
      final girls = PosProductFilter.apply(
        products: schoolWideProducts,
        schoolId: 'school-1',
        classId: 'class-1',
        gender: 'Girls',
      );

      expect(boys.products.map((product) => product.id),
          containsAll(['product-1', 'product-2', 'product-3']));
      expect(girls.products.map((product) => product.id),
          containsAll(['product-2', 'product-3', 'product-4']));
    });

    test('returns all school products when class scope is all', () {
      final result = PosProductFilter.apply(
        products: schoolWideProducts,
        schoolId: 'school-1',
        classId: null,
        gender: 'All',
      );

      expect(result.products.map((product) => product.id),
          containsAll(['product-1', 'product-2', 'product-3', 'product-4']));
      expect(result.products.map((product) => product.id),
          isNot(contains('product-5')));
    });
  });
}
