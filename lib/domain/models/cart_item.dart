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
}
