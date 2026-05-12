import '../../domain/models/product.dart';
import '../../domain/models/variant.dart';

class PosProductFilterResult {
  final List<Product> products;
  final int fetchedVariantCount;
  final int afterSchoolFilterCount;
  final int afterStatusFilterCount;
  final int afterClassFilterCount;
  final int afterGenderFilterCount;
  final int afterStockFilterCount;

  const PosProductFilterResult({
    required this.products,
    required this.fetchedVariantCount,
    required this.afterSchoolFilterCount,
    required this.afterStatusFilterCount,
    required this.afterClassFilterCount,
    required this.afterGenderFilterCount,
    required this.afterStockFilterCount,
  });

  int get finalVisibleCount => products.length;
}

class PosProductFilter {
  const PosProductFilter._();

  static PosProductFilterResult apply({
    required List<Product> products,
    required String schoolId,
    String? classId,
    String? gender,
    bool requireInStock = false,
  }) {
    final normalizedSchoolId = schoolId.trim();
    final normalizedClassId = classId?.trim();
    final normalizedGender = _normalizeGenderFilter(gender);
    final fetchedVariantCount = _variantCount(products);

    final schoolScoped = products
        .where((product) => product.schoolId.trim() == normalizedSchoolId)
        .toList(growable: false);
    final afterSchoolFilterCount = _variantCount(schoolScoped);

    final activeScoped = schoolScoped
        .map((product) {
          final visibleVariants = product.variants
              .where((variant) => variant.isVisibleInPos)
              .toList();
          if (!product.isVisibleInPos || visibleVariants.isEmpty) {
            return null;
          }
          return product.copyWith(variants: visibleVariants);
        })
        .whereType<Product>()
        .toList(growable: false);
    final afterStatusFilterCount = _variantCount(activeScoped);

    final classScoped = activeScoped
        .map((product) {
          if (normalizedClassId == null || normalizedClassId.isEmpty) {
            return product;
          }

          final visibleVariants = product.variants
              .where(
                (variant) => _matchesClass(
                  selectedClassId: normalizedClassId,
                  product: product,
                  variant: variant,
                ),
              )
              .toList();

          if (visibleVariants.isNotEmpty) {
            return product.copyWith(variants: visibleVariants);
          }

          if (_matchesProductClass(product, normalizedClassId)) {
            return product;
          }

          return null;
        })
        .whereType<Product>()
        .toList(growable: false);
    final afterClassFilterCount = _variantCount(classScoped);

    final genderScoped = classScoped
        .where(
          (product) => _matchesGender(
            product.gender,
            selectedGender: normalizedGender,
          ),
        )
        .toList(growable: false);
    final afterGenderFilterCount = _variantCount(genderScoped);

    final stockScoped = genderScoped
        .map((product) {
          if (!requireInStock) {
            return product;
          }

          final visibleVariants =
              product.variants.where((variant) => variant.stock > 0).toList();
          if (visibleVariants.isEmpty) {
            return null;
          }
          return product.copyWith(variants: visibleVariants);
        })
        .whereType<Product>()
        .toList(growable: false);

    return PosProductFilterResult(
      products: stockScoped,
      fetchedVariantCount: fetchedVariantCount,
      afterSchoolFilterCount: afterSchoolFilterCount,
      afterStatusFilterCount: afterStatusFilterCount,
      afterClassFilterCount: afterClassFilterCount,
      afterGenderFilterCount: afterGenderFilterCount,
      afterStockFilterCount: _variantCount(stockScoped),
    );
  }

  static int _variantCount(List<Product> products) {
    return products.fold<int>(
        0, (sum, product) => sum + product.variants.length);
  }

  static bool _matchesClass({
    required String selectedClassId,
    required Product product,
    required Variant variant,
  }) {
    if (variant.classIds.contains(selectedClassId)) {
      return true;
    }
    return _matchesProductClass(product, selectedClassId);
  }

  static bool _matchesProductClass(Product product, String selectedClassId) {
    if (product.classIds.contains(selectedClassId)) {
      return true;
    }
    return product.classId?.trim() == selectedClassId;
  }

  static bool _matchesGender(String? productGender, {String? selectedGender}) {
    if (selectedGender == null) {
      return true;
    }

    final normalizedProductGender = _normalizeGenderFilter(productGender);
    if (normalizedProductGender == null) {
      return true;
    }

    if (normalizedProductGender == selectedGender) {
      return true;
    }

    if (normalizedProductGender == 'Unisex') {
      return selectedGender == 'Male' ||
          selectedGender == 'Female' ||
          selectedGender == 'Unisex';
    }

    return false;
  }

  static String? _normalizeGenderFilter(String? gender) {
    final normalized = gender?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }

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
}
