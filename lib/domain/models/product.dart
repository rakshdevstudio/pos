import 'variant.dart';

class Product {
  final String id;
  final String schoolId;
  final String? classId;
  final List<String> classIds;
  final String? gender;
  final String name;
  final String? description;
  final String? imageUrl;
  final String? category;
  final int isActive;
  final String? status;
  final bool isHidden;
  final bool isArchived;
  final String? deletedAt;
  final String? updatedAt;
  final List<Variant> variants;

  const Product({
    required this.id,
    required this.schoolId,
    this.classId,
    this.classIds = const [],
    this.gender,
    required this.name,
    this.description,
    this.imageUrl,
    this.category,
    this.isActive = 1,
    this.status,
    this.isHidden = false,
    this.isArchived = false,
    this.deletedAt,
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
  bool get isVisibleInPos =>
      isActive != 0 && !isHidden && !isArchived && deletedAt == null;

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
      schoolId: _asString(
        json['school_id'] ??
            json['schoolId'] ??
            (json['school'] is Map<String, dynamic>
                ? (json['school'] as Map<String, dynamic>)['id']
                : null),
      ),
      classId: _asNullableString(json['class_id'] ?? json['classId']),
      classIds: _extractClassIds(json),
      gender: _asNullableString(json['gender']),
      name: _asString(json['name']),
      description: _asNullableString(json['description']),
      imageUrl: _asNullableString(json['image_url']),
      category: _asNullableString(json['category']),
      isActive: json['is_active'] ?? 1,
      status: _asNullableString(json['status']),
      isHidden: _asBool(json['hidden'] ?? json['is_hidden']),
      isArchived: _asBool(json['archived'] ?? json['is_archived']),
      deletedAt: _asNullableString(json['deleted_at']),
      updatedAt: json['updated_at'] as String?,
      variants: variantList,
    );
  }

  Product copyWith({
    List<String>? classIds,
    List<Variant>? variants,
  }) {
    return Product(
      id: id,
      schoolId: schoolId,
      classId: classId,
      classIds: classIds ?? this.classIds,
      gender: gender,
      name: name,
      description: description,
      imageUrl: imageUrl,
      category: category,
      isActive: isActive,
      status: status,
      isHidden: isHidden,
      isArchived: isArchived,
      deletedAt: deletedAt,
      updatedAt: updatedAt,
      variants: variants ?? this.variants,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'school_id': schoolId,
        'class_id': classId,
        'class_ids': classIds,
        'gender': gender,
        'name': name,
        'description': description,
        'image_url': imageUrl,
        'category': category,
        'is_active': isActive,
        'status': status,
        'hidden': isHidden,
        'archived': isArchived,
        'deleted_at': deletedAt,
        'updated_at': updatedAt,
        'variants': variants.map((v) => v.toJson()).toList(),
      };

  static String _asString(dynamic value) => value?.toString() ?? '';

  static String? _asNullableString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static List<String> _extractClassIds(Map<String, dynamic> json) {
    final ids = <String>{};

    void addValue(dynamic value) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) {
        ids.add(text);
      }
    }

    void addCollection(dynamic value) {
      if (value is Iterable) {
        for (final entry in value) {
          if (entry is Map<String, dynamic>) {
            addValue(entry['class_id'] ?? entry['id']);
          } else {
            addValue(entry);
          }
        }
        return;
      }

      if (value is String && value.contains(',')) {
        for (final part in value.split(',')) {
          addValue(part);
        }
        return;
      }

      addValue(value);
    }

    addCollection(json['class_ids']);
    addCollection(json['classIds']);
    addCollection(json['product_class_ids']);
    addCollection(json['classes']);
    addCollection(json['product_classes']);
    addCollection(json['class_id']);

    return ids.toList(growable: false);
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
}
