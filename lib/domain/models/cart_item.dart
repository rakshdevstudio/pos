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
        'quantity': quantity,
        'unit_price': variant.price,
        'line_total': lineTotal,
      };
}
