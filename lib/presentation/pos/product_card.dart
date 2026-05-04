import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/constants.dart';
import '../../core/providers/providers.dart';
import '../../domain/models/models.dart';
import '../../services/cart_service.dart';

class ProductCard extends StatefulWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final totalStock = widget.product.variants.fold<int>(
      0,
      (sum, v) => sum + v.stock,
    );
    final isOutOfStock = totalStock <= 0;
    final isLowStock =
        !isOutOfStock && totalStock <= PosConstants.lowStockThreshold;
    final canPurchase = widget.product.variants.any((v) => v.stock > 0);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: canPurchase ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: AppDimens.animMedium),
          decoration: BoxDecoration(
            color: _isHovered ? AppColors.surfaceElevated : AppColors.surface,
            borderRadius: BorderRadius.circular(AppDimens.radiusLG),
            border: Border.all(
              color: _isHovered ? AppColors.borderFocus : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image
              Expanded(
                flex: 5,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppDimens.radiusLG),
                      ),
                      child: widget.product.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: widget.product.imageUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              placeholder: (_, __) => Container(
                                color: AppColors.surfaceHighlight,
                                child: const Center(
                                  child: Icon(
                                    Icons.image_outlined,
                                    color: AppColors.textDisabled,
                                    size: 32,
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => _placeholder(),
                            )
                          : _placeholder(),
                    ),
                    Positioned(
                      bottom: AppDimens.spacingMD,
                      left: AppDimens.spacingMD,
                      child: _StockBadge(
                        label: isOutOfStock
                            ? 'Out of stock'
                            : isLowStock
                                ? 'Low stock'
                                : 'In stock',
                        tone: isOutOfStock
                            ? _StockBadgeTone.error
                            : isLowStock
                                ? _StockBadgeTone.warning
                                : _StockBadgeTone.success,
                      ),
                    ),
                    Positioned(
                      bottom: AppDimens.spacingMD,
                      right: AppDimens.spacingMD,
                      child: GestureDetector(
                        onTap: canPurchase ? widget.onTap : null,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: canPurchase
                                ? AppColors.accent
                                : AppColors.textDisabled,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.background.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: AppColors.background,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Product info
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.spacingLG,
                    vertical: 2,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.product.name.toUpperCase(),
                          style: AppTypography.labelLarge.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.product.variants.isEmpty
                              ? 'No variants'
                              : widget.product.variants.length > 1
                                  ? '₹${widget.product.minPrice.toStringAsFixed(0)} – ₹${widget.product.maxPrice.toStringAsFixed(0)} • ${widget.product.variants.length} sizes'
                                  : '₹${widget.product.minPrice.toStringAsFixed(0)}',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surfaceElevated,
      child: const Center(
        child: Icon(
          Icons.checkroom_outlined,
          color: AppColors.textDisabled,
          size: 36,
        ),
      ),
    );
  }
}

class _StockBadge extends StatelessWidget {
  final String label;
  final _StockBadgeTone tone;

  const _StockBadge({
    required this.label,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = switch (tone) {
      _StockBadgeTone.success => AppColors.background.withValues(alpha: 0.72),
      _StockBadgeTone.warning => AppColors.warning.withValues(alpha: 0.92),
      _StockBadgeTone.error => AppColors.error.withValues(alpha: 0.9),
    };
    final textColor = tone == _StockBadgeTone.success
        ? AppColors.textPrimary
        : AppColors.background;

    return Container(
      constraints: const BoxConstraints(maxWidth: 88),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.spacingSM,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelMedium.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

enum _StockBadgeTone { success, warning, error }

// Variant selection bottom sheet
class VariantSheet extends ConsumerWidget {
  final Product product;

  const VariantSheet({super.key, required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variants = product.variants;
    final mediaQuery = MediaQuery.of(context);
    final maxSheetHeight = mediaQuery.size.height * 0.88;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDimens.radiusXXL),
          ),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: AppDimens.spacingMD),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderFocus,
                  borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                ),
              ),
            ),

            // Product header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimens.spacingXXL,
                AppDimens.spacingXL,
                AppDimens.spacingXXL,
                0,
              ),
              child: Row(
                children: [
                  if (product.imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                      child: CachedNetworkImage(
                        imageUrl: product.imageUrl!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 56,
                          height: 56,
                          color: AppColors.surfaceElevated,
                          child: const Icon(Icons.checkroom_outlined,
                              color: AppColors.textMuted),
                        ),
                      ),
                    ),
                  if (product.imageUrl != null)
                    const SizedBox(width: AppDimens.spacingMD),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: AppTypography.headlineSmall.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (product.category != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            product.category!,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textMuted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppDimens.spacingXL),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppDimens.spacingXXL),
              child: Text(
                AppStrings.selectVariant,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textMuted,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: AppDimens.spacingMD),

            // Variants list
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.only(
                  bottom: mediaQuery.padding.bottom + AppDimens.spacingXL,
                ),
                itemCount: variants.length,
                itemBuilder: (context, index) {
                  final variant = variants[index];
                  return _VariantTile(
                    product: product,
                    variant: variant,
                    onAdd: () {
                      final result = ref
                          .read(cartProvider.notifier)
                          .addItemWithResult(product, variant);
                      if (result != CartAddResult.added) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              result == CartAddResult.stockLimitReached
                                  ? 'Only ${variant.stock} available'
                                  : 'Out of stock',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(context);
                      ref.read(scannerRefocusRequestProvider.notifier).state++;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              Icon(
                                variant.stock <= PosConstants.lowStockThreshold
                                    ? Icons.warning_amber_rounded
                                    : Icons.check_circle_rounded,
                                color: variant.stock <=
                                        PosConstants.lowStockThreshold
                                    ? AppColors.warning
                                    : AppColors.success,
                                size: 16,
                              ),
                              const SizedBox(width: AppDimens.spacingSM),
                              Expanded(
                                child: Text(
                                  variant.stock <=
                                          PosConstants.lowStockThreshold
                                      ? '${product.name} (${variant.size}) added • Low stock'
                                      : '${product.name} (${variant.size}) added',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantTile extends StatelessWidget {
  final Product product;
  final Variant variant;
  final VoidCallback onAdd;

  const _VariantTile({
    required this.product,
    required this.variant,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final canAdd = (variant.stock) > 0;
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppDimens.spacingXXL,
        vertical: AppDimens.spacingXS,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.spacingLG,
          vertical: AppDimens.spacingXS,
        ),
        title: Text(
          'Size ${variant.size}',
          style: AppTypography.titleMedium.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: variant.sku != null
            ? Text(
                'SKU: ${variant.sku} · ${_stockText(variant)}',
                style: AppTypography.bodySmall.copyWith(
                  color: canAdd ? AppColors.textMuted : AppColors.error,
                ),
              )
            : Text(
                _stockText(variant),
                style: AppTypography.bodySmall.copyWith(
                  color: canAdd ? AppColors.textMuted : AppColors.error,
                ),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '₹${variant.price.toStringAsFixed(0)}',
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppDimens.spacingMD),
            GestureDetector(
              onTap: canAdd ? onAdd : null,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: canAdd ? AppColors.accent : AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(AppDimens.radiusSM),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: AppColors.background,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stockText(Variant variant) {
    if (variant.stock <= 0) return 'Out of stock';
    if (variant.stock <= PosConstants.lowStockThreshold) {
      return 'Low stock: ${variant.stock} left';
    }
    return 'In stock';
  }
}
