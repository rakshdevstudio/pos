class Variant {
  final int id;
  final int productId;
  final String size;
  final double price;
  final String? sku;
  final int? stockQuantity;

  const Variant({
    required this.id,
    required this.productId,
    required this.size,
    required this.price,
    this.sku,
    this.stockQuantity,
  });

  factory Variant.fromJson(Map<String, dynamic> json) {
    return Variant(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      size: json['size'] as String,
      price: (json['price'] as num).toDouble(),
      sku: json['sku'] as String?,
      stockQuantity: json['stock_quantity'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'product_id': productId,
        'size': size,
        'price': price,
        'sku': sku,
        'stock_quantity': stockQuantity,
      };
}
