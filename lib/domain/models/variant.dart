class Variant {
  final String id;
  final String productId;
  final String name;
  final String? sku;
  final String? barcode;
  final List<String> classIds;
  final double price;
  final int stock;
  final int isActive;
  final String? status;
  final bool isHidden;
  final String? updatedAt;

  // Compatibility aliases for existing UI and repositories
  String get size => name;
  int get stockQuantity => stock;

  const Variant({
    required this.id,
    required this.productId,
    required this.name,
    this.sku,
    this.barcode,
    this.classIds = const [],
    required this.price,
    this.stock = 0,
    this.isActive = 1,
    this.status,
    this.isHidden = false,
    this.updatedAt,
  });

  factory Variant.fromJson(Map<String, dynamic> json) {
    final stockValue = json['stock'] ?? json['stock_quantity'] ?? 0;
    return Variant(
      id: _asString(json['id']),
      productId: _asString(json['product_id']),
      name: _asString(json['name'] ?? json['size']),
      sku: _asNullableString(json['sku']),
      barcode: _asNullableString(
        json['barcode'] ?? json['barcode_value'] ?? json['sku'],
      ),
      classIds: _extractClassIds(json),
      price: (json['price'] as num).toDouble(),
      stock: _asInt(stockValue).clamp(0, 1 << 31),
      isActive: json['is_active'] ?? 1,
      status: _asNullableString(json['status']),
      isHidden: _asBool(json['hidden'] ?? json['is_hidden']),
      updatedAt: json['updated_at'] as String?,
    );
  }

  Variant copyWith({
    List<String>? classIds,
    int? stock,
  }) {
    return Variant(
      id: id,
      productId: productId,
      name: name,
      sku: sku,
      barcode: barcode,
      classIds: classIds ?? this.classIds,
      price: price,
      stock: stock ?? this.stock,
      isActive: isActive,
      status: status,
      isHidden: isHidden,
      updatedAt: updatedAt,
    );
  }

  bool get isVisibleInPos => isActive != 0 && !isHidden;

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': productId,
        'size': name, // fallback mapped to old key for backwards compat
        'name': name,
        'price': price,
        'sku': sku,
        'barcode': barcode,
        'barcode_value': barcode,
        'class_ids': classIds,
        'stock_quantity': stock,
        'stock': stock,
        'is_active': isActive,
        'status': status,
        'hidden': isHidden,
        'updated_at': updatedAt,
      };

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

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
    addCollection(json['variant_class_ids']);
    addCollection(json['classes']);
    addCollection(json['product_classes']);
    addCollection(json['variant_classes']);
    addCollection(json['class_id']);

    return ids.toList(growable: false);
  }

  static bool _asBool(dynamic value) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
}
