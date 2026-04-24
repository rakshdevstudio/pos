import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/constants.dart';
import '../../domain/models/models.dart';
import '../../services/cart_service.dart';
import '../../services/sync_service.dart';
import '../shared/widgets/illume_button.dart';
import '../checkout/customer_details_sheet.dart';
import '../checkout/checkout_sheet.dart';
import 'numpad_sheet.dart';

final _currencyFmt = NumberFormat('#,##0', 'en_IN');

class CartPanel extends ConsumerStatefulWidget {
  const CartPanel({super.key});

  @override
  ConsumerState<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<CartPanel> {
  final ScrollController _scrollController = ScrollController();
  int _lastCartLength = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<CartState>(cartProvider, (previous, next) {
      if (next.items.length > _lastCartLength) {
        // Auto scroll to bottom smoothly
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent + 100,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
      _lastCartLength = next.items.length;
    });

    final cart = ref.watch(cartProvider);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.cartBg,
        border: Border(
          right: BorderSide(color: AppColors.border),
        ),
      ),
      child: Column(
        children: [
          // Cart header
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimens.spacingXXL,
              vertical: AppDimens.spacingXL,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border),
              ),
            ),
            child: Row(
              children: [
                Text(
                  AppStrings.cart,
                  style: AppTypography.headlineSmall.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (cart.items.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppDimens.radiusLG),
                          ),
                          title: Text(
                            'Clear Cart?',
                            style: AppTypography.headlineSmall.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                          content: Text(
                            'All items will be removed.',
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                ref.read(cartProvider.notifier).clearCart();
                                Navigator.pop(context);
                              },
                              child: const Text(
                                'Clear',
                                style:
                                    TextStyle(color: AppColors.error),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Text(
                      'Clear',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Items list
          Expanded(
            child: cart.items.isEmpty
                ? _emptyCart()
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppDimens.spacingMD,
                    ),
                    itemCount: cart.items.length,
                    separatorBuilder: (_, __) => const Divider(
                      color: AppColors.border,
                      height: 1,
                      indent: AppDimens.spacingXXL,
                      endIndent: AppDimens.spacingXXL,
                    ),
                    itemBuilder: (context, index) {
                      final itemKey = cart.items[index].key;
                      return _CartItemTile(itemId: itemKey);
                    },
                  ),
          ),

          // Total + Checkout
          _CartFooter(cart: cart),
        ],
      ),
    );
  }

  Widget _emptyCart() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.shopping_bag_outlined,
            size: 48,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: AppDimens.spacingMD),
          Text(
            AppStrings.emptyCart,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: AppDimens.spacingXS),
          Text(
            AppStrings.emptyCartSub,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textDisabled,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CartItemTile extends ConsumerWidget {
  final String itemId;

  const _CartItemTile({required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Graceful fallback for dismissed items actively animating out
    final item = ref.watch(
      cartProvider.select(
        (c) => c.items.cast<CartItem?>().firstWhere((e) => e?.key == itemId, orElse: () => null),
      ),
    );

    if (item == null) return const SizedBox.shrink();

    return Dismissible(
      key: ValueKey(item.key),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {
        DismissDirection.endToStart: 0.45,
      },
      onDismissed: (direction) {
        HapticFeedback.mediumImpact();
        ref.read(cartProvider.notifier).removeItem(item.key);
        
        // Custom undo snackbar
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item.product.name} removed'),
            backgroundColor: AppColors.surfaceElevated,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'UNDO',
              textColor: AppColors.accent,
              onPressed: () {
                ref.read(cartProvider.notifier).undo();
              },
            ),
          ),
        );
      },
      background: Container(
        color: AppColors.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppDimens.spacingXXL),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.background),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.spacingXXL,
          vertical: AppDimens.spacingMD,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Size ${item.variant.size} · ₹${item.variant.price.toStringAsFixed(0)}',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: AppDimens.spacingMD),

          // Quantity controls
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${_currencyFmt.format(item.lineTotal)}',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppDimens.spacingXS),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QtyButton(
                    icon: item.quantity <= 1
                        ? Icons.delete_outline_rounded
                        : Icons.remove_rounded,
                    color: item.quantity <= 1
                        ? AppColors.error
                        : AppColors.textMuted,
                    onTap: () => ref
                        .read(cartProvider.notifier)
                        .decrementQuantity(item.key),
                  ),
                  GestureDetector(
                    onLongPress: () async {
                      HapticFeedback.lightImpact();
                      final newValue = await showModalBottomSheet<int>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => NumpadSheet(
                          initialValue: item.quantity,
                          title: 'SET QUANTITY',
                        ),
                      );
                      if (newValue != null && newValue >= 0) {
                        ref.read(cartProvider.notifier).setQuantity(item.key, newValue);
                      }
                    },
                    child: SizedBox(
                      width: 32,
                      child: Text(
                        '${item.quantity}',
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  _QtyButton(
                    icon: Icons.add_rounded,
                    color: AppColors.textMuted,
                    onTap: () => ref
                        .read(cartProvider.notifier)
                        .incrementQuantity(item.key),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ));
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QtyButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusSM),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }
}

class _CartFooter extends ConsumerWidget {
  final CartState cart;

  const _CartFooter({required this.cart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.all(AppDimens.spacingXXL),
      child: Column(
        children: [
          // Subtotal
          if (cart.discountAmount > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.subtotal,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '₹${_currencyFmt.format(cart.subtotal)}',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.spacingXS),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.discount,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.success,
                  ),
                ),
                Text(
                  '− ₹${_currencyFmt.format(cart.discountAmount)}',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.spacingMD),
            const Divider(color: AppColors.border),
            const SizedBox(height: AppDimens.spacingMD),
          ],

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.total.toUpperCase(),
                style: AppTypography.titleLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              Text(
                '₹${_currencyFmt.format(cart.total)}',
                style: AppTypography.monoPrice.copyWith(
                  color: AppColors.accent,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppDimens.spacingXL),

          // Checkout button
          AnimatedOpacity(
            opacity: cart.items.isEmpty ? 0.4 : 1.0,
            duration: const Duration(milliseconds: AppDimens.animMedium),
            child: IllumeButton(
              label: '${AppStrings.checkout.toUpperCase()} · ${cart.itemCount}',
              icon: Icons.point_of_sale_rounded,
              height: AppDimens.buttonHeightLG,
              onPressed: cart.items.isEmpty
                  ? null
                  : () async {
                      final customer = await showModalBottomSheet<CustomerInfo>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => CustomerDetailsSheet(),
                      );

                      if (customer != null && context.mounted) {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => CheckoutSheet(customer: customer),
                        );
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }
}

