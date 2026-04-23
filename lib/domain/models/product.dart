import 'variant.dart';

class Product {
  final int id;
  final int schoolId;
  final String name;
  final String? description;
  final String? imageUrl;
  final String? category;
  final List<Variant> variants;

  const Product({
    required this.id,
    required this.schoolId,
    required this.name,
    this.description,
    this.imageUrl,
    this.category,
    this.variants = const [],
  });

  double get minPrice =>
      variants.isEmpty ? 0 : variants.map((v) => v.price).reduce((a, b) => a < b ? a : b);

  double get maxPrice =>
      variants.isEmpty ? 0 : variants.map((v) => v.price).reduce((a, b) => a > b ? a : b);

  factory Product.fromJson(Map<String, dynamic> json) {
    final variantList = (json['variants'] as List<dynamic>?)
            ?.map((v) => Variant.fromJson(v as Map<String, dynamic>))
            .toList() ??
        [];

    return Product(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      category: json['category'] as String?,
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
        'variants': variants.map((v) => v.toJson()).toList(),
      };
}
