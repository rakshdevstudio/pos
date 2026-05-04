import 'variant.dart';
import 'product.dart';

class CartItem {
  final Product product;
  final Variant variant;
  int quantity;

  CartItem({
    required this.product,
    required this.variant,
    this.quantity = 1,
  });

  double get lineTotal => variant.price * quantity;

  CartItem copyWith({int? quantity}) {
    return CartItem(
      product: product,
      variant: variant,
      quantity: quantity ?? this.quantity,
    );
  }

  Map<String, dynamic> toJson() => {
        'product': product.toJson(),
        'variant': variant.toJson(),
        'quantity': quantity,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final productJson = json['product'];
    final variantJson = json['variant'];

    return CartItem(
      product: Product.fromJson(
        productJson is Map<String, dynamic>
            ? productJson
            : const <String, dynamic>{},
      ),
      variant: Variant.fromJson(
        variantJson is Map<String, dynamic>
            ? variantJson
            : const <String, dynamic>{'price': 0},
      ),
      quantity: _asInt(json['quantity']).clamp(1, 1 << 31),
    );
  }

  /// Unique key for deduplication — product + variant
  String get key => '${product.id}_${variant.id}';

  Map<String, dynamic> toOrderLine() => {
        'product_id': product.id,
        'variant_id': variant.id,
        'product_name': product.name,
        'variant_name': _formatVariantLabel(variant.name),
        'size': variant.name,
        'sku': variant.sku,
        'school_id': product.schoolId,
        'school_name': null,
        'category': product.category,
        'image_url': product.imageUrl,
        'quantity': quantity,
        'unit_price': variant.price,
        'line_total': lineTotal,
        'name': '${product.name} (${_formatVariantLabel(variant.name)})',
        'title': '${product.name} (${_formatVariantLabel(variant.name)})',
        'display_name':
            '${product.name} (${_formatVariantLabel(variant.name)})',
        'product_snapshot': {
          'product_name': product.name,
          'variant_name': _formatVariantLabel(variant.name),
          'size': variant.name,
          'school_name': null,
          'image_url': product.imageUrl,
          'sku': variant.sku,
        },
      };

  String _formatVariantLabel(String variantName) {
    final trimmed = variantName.trim();
    if (trimmed.isEmpty) return 'Size';
    if (trimmed.toLowerCase().startsWith('size ')) return trimmed;
    return 'Size $trimmed';
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 1;
  }
}
