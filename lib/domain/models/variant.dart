class Variant {
  final String id;
  final String productId;
  final String name;
  final String? barcode;
  final double price;
  final int stock;
  final int isActive;
  final String? updatedAt;

  // Compatibility aliases for existing UI and repositories
  String get size => name;
  String? get sku => barcode;
  int get stockQuantity => stock;

  const Variant({
    required this.id,
    required this.productId,
    required this.name,
    this.barcode,
    required this.price,
    this.stock = 0,
    this.isActive = 1,
    this.updatedAt,
  });

  factory Variant.fromJson(Map<String, dynamic> json) {
    final stockValue = json['stock'] ?? json['stock_quantity'] ?? 0;
    return Variant(
      id: _asString(json['id']),
      productId: _asString(json['product_id']),
      name: _asString(json['name'] ?? json['size']),
      barcode: _asNullableString(json['barcode'] ?? json['sku']),
      price: (json['price'] as num).toDouble(),
      stock: _asInt(stockValue).clamp(0, 1 << 31),
      isActive: json['is_active'] ?? 1,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Variant copyWith({
    int? stock,
  }) {
    return Variant(
      id: id,
      productId: productId,
      name: name,
      barcode: barcode,
      price: price,
      stock: stock ?? this.stock,
      isActive: isActive,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': productId,
        'size': name, // fallback mapped to old key for backwards compat
        'name': name,
        'price': price,
        'sku': barcode,
        'barcode': barcode,
        'stock_quantity': stock,
        'stock': stock,
        'is_active': isActive,
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
}
