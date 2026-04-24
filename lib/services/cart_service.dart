import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/models.dart';

class CartState {
  final List<CartItem> items;
  final double discountAmount;
  final bool isPercentDiscount;
  final double discountValue;

  const CartState({
    this.items = const [],
    this.discountAmount = 0,
    this.isPercentDiscount = false,
    this.discountValue = 0,
  });

  double get subtotal => items.fold(0, (sum, item) => sum + item.lineTotal);

  double get total => (subtotal - discountAmount).clamp(0, double.infinity);

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  CartState copyWith({
    List<CartItem>? items,
    double? discountAmount,
    bool? isPercentDiscount,
    double? discountValue,
  }) {
    return CartState(
      items: items ?? this.items,
      discountAmount: discountAmount ?? this.discountAmount,
      isPercentDiscount: isPercentDiscount ?? this.isPercentDiscount,
      discountValue: discountValue ?? this.discountValue,
    );
  }
}

class CartNotifier extends StateNotifier<CartState> {
  final List<CartState> _history = [];
  static const _maxHistory = 10;

  CartNotifier() : super(const CartState());

  void _pushSnapshot() {
    _history.add(state);
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
    }
  }

  void undo() {
    if (_history.isEmpty) return;
    state = _history.removeLast();
  }

  void invalidateHistory() {
    _history.clear();
  }

  bool addItem(Product product, Variant variant) {
    if (variant.stock <= 0) return false;

    // we don't save history on single add, only destructive ops
    final existing =
        state.items.where((i) => i.key == '${product.id}_${variant.id}');

    if (existing.isNotEmpty) {
      var changed = false;
      final updated = state.items.map((i) {
        if (i.key == '${product.id}_${variant.id}') {
          if (i.quantity >= variant.stock) return i;
          changed = true;
          return i.copyWith(quantity: i.quantity + 1);
        }
        return i;
      }).toList();
      if (!changed) return false;
      state = state.copyWith(items: updated);
    } else {
      state = state.copyWith(
        items: [...state.items, CartItem(product: product, variant: variant)],
      );
    }
    _recalcDiscount();
    return true;
  }

  void removeItem(String key) {
    _pushSnapshot();
    state = state.copyWith(
      items: state.items.where((i) => i.key != key).toList(),
    );
    _recalcDiscount();
  }

  bool incrementQuantity(String key) {
    var changed = false;
    final updated = state.items.map((i) {
      if (i.key == key) {
        if (i.quantity >= i.variant.stock) {
          return i;
        }
        changed = true;
        return i.copyWith(quantity: i.quantity + 1);
      }
      return i;
    }).toList();
    if (!changed) return false;
    state = state.copyWith(items: updated);
    _recalcDiscount();
    return true;
  }

  void decrementQuantity(String key) {
    final item = state.items.firstWhere((i) => i.key == key);
    if (item.quantity <= 1) {
      // Removing via decrement
      removeItem(key);
    } else {
      final updated = state.items.map((i) {
        if (i.key == key) return i.copyWith(quantity: i.quantity - 1);
        return i;
      }).toList();
      state = state.copyWith(items: updated);
      _recalcDiscount();
    }
  }

  void restoreItem(CartItem item, int index) {
    // Left for legacy compatibility. We now use undo() instead.
    undo();
  }

  void setQuantity(String key, int quantity) {
    if (quantity <= 0) {
      removeItem(key);
      return;
    }
    final updated = state.items.map((i) {
      if (i.key == key) {
        final safeQuantity = quantity.clamp(1, i.variant.stock);
        return i.copyWith(quantity: safeQuantity);
      }
      return i;
    }).toList();
    state = state.copyWith(items: updated);
    _recalcDiscount();
  }

  void setDiscount({required double value, required bool isPercent}) {
    double amount = 0;
    if (isPercent) {
      amount = state.subtotal * (value / 100);
    } else {
      amount = value;
    }
    state = state.copyWith(
      discountValue: value,
      isPercentDiscount: isPercent,
      discountAmount: amount,
    );
  }

  void _recalcDiscount() {
    if (state.discountValue > 0) {
      setDiscount(
        value: state.discountValue,
        isPercent: state.isPercentDiscount,
      );
    }
  }

  void clearCart() {
    _pushSnapshot();
    state = const CartState();
  }

  void processCheckout() {
    invalidateHistory();
    state = const CartState();
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>(
  (ref) => CartNotifier(),
);
