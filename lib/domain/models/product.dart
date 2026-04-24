import 'variant.dart';

class Product {
  final String id;
  final String schoolId;
  final String name;
  final String? description;
  final String? imageUrl;
  final String? category;
  final int isActive;
  final String? updatedAt;
  final List<Variant> variants;

  const Product({
    required this.id,
    required this.schoolId,
    required this.name,
    this.description,
    this.imageUrl,
    this.category,
    this.isActive = 1,
    this.updatedAt,
    this.variants = const [],
  });

  double get minPrice => variants.isEmpty
      ? 0
      : variants.map((v) => v.price).reduce((a, b) => a < b ? a : b);

  double get maxPrice => variants.isEmpty
      ? 0
      : variants.map((v) => v.price).reduce((a, b) => a > b ? a : b);

  bool get hasPurchasableVariant => variants.any((v) => v.stock > 0);

  factory Product.fromJson(Map<String, dynamic> json) {
    final seenVariantIds = <String>{};
    final variantList = <Variant>[];
    for (final entry in (json['variants'] as List<dynamic>? ?? [])) {
      final variant = Variant.fromJson(entry as Map<String, dynamic>);
      if (seenVariantIds.add(variant.id)) {
        variantList.add(variant);
      }
    }

    return Product(
      id: _asString(json['id']),
      schoolId: _asString(json['school_id']),
      name: _asString(json['name']),
      description: _asNullableString(json['description']),
      imageUrl: _asNullableString(json['image_url']),
      category: _asNullableString(json['category']),
      isActive: json['is_active'] ?? 1,
      updatedAt: json['updated_at'] as String?,
      variants: variantList,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'school_id': schoolId,
        'name': name,
        'description': description,
        'image_url': imageUrl,
        'category': category,
        'is_active': isActive,
        'updated_at': updatedAt,
        'variants': variants.map((v) => v.toJson()).toList(),
      };

  static String _asString(dynamic value) => value?.toString() ?? '';

  static String? _asNullableString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
