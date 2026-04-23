import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/constants.dart';
import '../../domain/models/models.dart';
import '../../services/cart_service.dart';
import '../checkout/checkout_screen.dart';

final _currencyFmt = NumberFormat('#,##0', 'en_IN');

class CartPanel extends ConsumerWidget {
  const CartPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      final item = cart.items[index];
                      return _CartItemTile(item: item);
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
  final CartItem item;

  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
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
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${item.quantity}',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
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
    );
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
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusXS),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 14, color: color),
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
                AppStrings.total,
                style: AppTypography.headlineSmall.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '₹${_currencyFmt.format(cart.total)}',
                style: AppTypography.monoPrice.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppDimens.spacingXL),

          // Checkout button
          AnimatedOpacity(
            opacity: cart.items.isEmpty ? 0.4 : 1.0,
            duration: const Duration(milliseconds: AppDimens.animMedium),
            child: SizedBox(
              width: double.infinity,
              height: AppDimens.buttonHeightLG,
              child: ElevatedButton(
                onPressed: cart.items.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => const CheckoutScreen(),
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.background,
                  disabledBackgroundColor:
                      AppColors.accent.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimens.radiusMD),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.point_of_sale_rounded, size: 20),
                    const SizedBox(width: AppDimens.spacingSM),
                    Text(
                      '${AppStrings.checkout} · ${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}',
                      style: AppTypography.titleLarge.copyWith(
                        color: AppColors.background,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

