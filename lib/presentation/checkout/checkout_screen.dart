import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/constants.dart';
import '../../data/remote/api_client.dart';
import '../../data/repositories/order_repository_impl.dart';
import '../../domain/models/models.dart';
import '../../services/cart_service.dart';
import '../shared/widgets/illume_button.dart';
import 'upi_screen.dart';

final _currencyFmt = NumberFormat('#,##0', 'en_IN');
final _discountValueProvider = StateProvider<double>((ref) => 0);
final _isPercentDiscountProvider = StateProvider<bool>((ref) => false);
final _selectedPaymentProvider =
    StateProvider<PaymentMethod?>((ref) => null);
final _orderPlacingProvider = StateProvider<bool>((ref) => false);

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen>
    with SingleTickerProviderStateMixin {
  final _discountController = TextEditingController();
  late AnimationController _animController;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    final cart = ref.read(cartProvider);
    final payment = ref.read(_selectedPaymentProvider);
    if (payment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a payment method')),
      );
      return;
    }

    if (payment == PaymentMethod.upi) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UpiScreen(total: cart.total),
        ),
      ).then((_) => _finalizeOrder());
      return;
    }

    await _finalizeOrder();
  }

  Future<void> _finalizeOrder() async {
    final cart = ref.read(cartProvider);
    final payment =
        ref.read(_selectedPaymentProvider) ?? PaymentMethod.cash;

    ref.read(_orderPlacingProvider.notifier).state = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final schoolId = prefs.getInt('selected_school_id') ?? 0;

      final order = Order(
        offlineId: const Uuid().v4(),
        schoolId: schoolId,
        items: cart.items,
        subtotal: cart.subtotal,
        discountAmount: cart.discountAmount,
        total: cart.total,
        paymentMethod: payment,
        createdAt: DateTime.now(),
      );

      final repo = OrderRepositoryImpl(ApiClient());
      await repo.saveOrderLocally(order);

      // Attempt immediate sync
      repo.syncOrder(order);

      ref.read(cartProvider.notifier).clearCart();

      if (mounted) {
        _showSuccessSheet();
      }
    } finally {
      if (mounted) {
        ref.read(_orderPlacingProvider.notifier).state = false;
      }
    }
  }

  void _showSuccessSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderSuccessSheet(
        onNewOrder: () {
          Navigator.of(context).popUntil((r) => r.isFirst);
        },
        onPrint: () async {
          Navigator.pop(context);
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.success, size: 16),
                    const SizedBox(width: AppDimens.spacingSM),
                    Text('Receipt sent to printer',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textPrimary)),
                  ],
                ),
              ),
            );
            if (mounted) Navigator.pop(context);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final isPercent = ref.watch(_isPercentDiscountProvider);
    final selectedPayment = ref.watch(_selectedPaymentProvider);
    final isPlacing = ref.watch(_orderPlacingProvider);

    // Apply discount on controller change
    ref.listen(_discountValueProvider, (_, val) {
      ref.read(cartProvider.notifier).setDiscount(
            value: val,
            isPercent: isPercent,
          );
    });
    ref.listen(_isPercentDiscountProvider, (_, isP) {
      final val = ref.read(_discountValueProvider);
      ref.read(cartProvider.notifier).setDiscount(
            value: val,
            isPercent: isP,
          );
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SlideTransition(
        position: _slideAnim,
        child: SafeArea(
          child: Column(
            children: [
              // Header
              _buildHeader(context),
              const Divider(height: 1, color: AppColors.border),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppDimens.spacingXXL),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bill summary
                      _buildBillSummary(cart),
                      const SizedBox(height: AppDimens.spacingXXL),

                      // Discount
                      _buildDiscountSection(cart, isPercent),
                      const SizedBox(height: AppDimens.spacingXXL),

                      // Final total
                      _buildFinalTotal(cart),
                      const SizedBox(height: AppDimens.spacingXXL),

                      // Payment methods
                      _buildPaymentSection(selectedPayment),
                      const SizedBox(height: AppDimens.spacing3XL),

                      // Confirm button
                      IllumeButton(
                        label: AppStrings.confirmPayment,
                        onPressed:
                            selectedPayment == null ? null : _placeOrder,
                        isLoading: isPlacing,
                        icon: Icons.check_rounded,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: AppDimens.appBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.spacingXL),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: AppDimens.spacingSM),
          Text(
            AppStrings.payment,
            style: AppTypography.headlineSmall.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillSummary(CartState cart) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bill Summary',
          style: AppTypography.titleLarge.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: AppDimens.spacingMD),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppDimens.radiusLG),
            border: Border.all(color: AppColors.border),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cart.items.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (_, i) {
              final item = cart.items[i];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.spacingXL,
                  vertical: AppDimens.spacingMD,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.product.name,
                            style: AppTypography.titleMedium.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Size ${item.variant.size} × ${item.quantity}',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${_currencyFmt.format(item.lineTotal)}',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDiscountSection(CartState cart, bool isPercent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.discountLabel,
          style: AppTypography.titleLarge.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: AppDimens.spacingMD),
        Row(
          children: [
            // Toggle ₹ / %
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  _DiscountToggleBtn(
                    label: AppStrings.flatToggle,
                    isActive: !isPercent,
                    onTap: () => ref
                        .read(_isPercentDiscountProvider.notifier)
                        .state = false,
                  ),
                  _DiscountToggleBtn(
                    label: AppStrings.percentToggle,
                    isActive: isPercent,
                    onTap: () => ref
                        .read(_isPercentDiscountProvider.notifier)
                        .state = true,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppDimens.spacingMD),
            Expanded(
              child: TextField(
                controller: _discountController,
                keyboardType: TextInputType.number,
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
                cursorColor: AppColors.accent,
                onChanged: (val) {
                  ref.read(_discountValueProvider.notifier).state =
                      double.tryParse(val) ?? 0;
                },
                decoration: InputDecoration(
                  hintText: isPercent ? 'e.g. 10' : 'e.g. 100',
                  hintStyle: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textMuted,
                  ),
                  suffixText: isPercent ? '%' : '₹',
                  suffixStyle: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimens.radiusMD),
                    borderSide:
                        const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimens.radiusMD),
                    borderSide:
                        const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimens.radiusMD),
                    borderSide: const BorderSide(
                        color: AppColors.accent, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.spacingLG,
                    vertical: AppDimens.spacingMD,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFinalTotal(CartState cart) {
    return Container(
      padding: const EdgeInsets.all(AppDimens.spacingXXL),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _TotalRow(
            label: AppStrings.subtotal,
            value: '₹${_currencyFmt.format(cart.subtotal)}',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (cart.discountAmount > 0) ...[
            const SizedBox(height: AppDimens.spacingSM),
            _TotalRow(
              label: AppStrings.discount,
              value: '− ₹${_currencyFmt.format(cart.discountAmount)}',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.success,
              ),
              valueStyle: AppTypography.bodyMedium.copyWith(
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: AppDimens.spacingMD),
            const Divider(color: AppColors.border),
          ],
          const SizedBox(height: AppDimens.spacingMD),
          _TotalRow(
            label: AppStrings.total,
            value: '₹${_currencyFmt.format(cart.total)}',
            style: AppTypography.headlineSmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            valueStyle: AppTypography.monoPrice.copyWith(
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSection(PaymentMethod? selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Method',
          style: AppTypography.titleLarge.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: AppDimens.spacingMD),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: AppDimens.spacingMD,
          mainAxisSpacing: AppDimens.spacingMD,
          childAspectRatio: 2.5,
          children: [
            _PaymentBtn(
              label: AppStrings.cash,
              icon: Icons.payments_outlined,
              method: PaymentMethod.cash,
              selected: selected,
              onTap: () => ref.read(_selectedPaymentProvider.notifier).state =
                  PaymentMethod.cash,
            ),
            _PaymentBtn(
              label: AppStrings.upi,
              icon: Icons.qr_code_rounded,
              method: PaymentMethod.upi,
              selected: selected,
              onTap: () => ref.read(_selectedPaymentProvider.notifier).state =
                  PaymentMethod.upi,
            ),
            _PaymentBtn(
              label: AppStrings.card,
              icon: Icons.credit_card_rounded,
              method: PaymentMethod.card,
              selected: selected,
              onTap: () => ref.read(_selectedPaymentProvider.notifier).state =
                  PaymentMethod.card,
            ),
            _PaymentBtn(
              label: AppStrings.split,
              icon: Icons.call_split_rounded,
              method: PaymentMethod.split,
              selected: selected,
              onTap: () => ref.read(_selectedPaymentProvider.notifier).state =
                  PaymentMethod.split,
            ),
          ],
        ),
      ],
    );
  }
}

// Helper widgets

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? style;
  final TextStyle? valueStyle;

  const _TotalRow({
    required this.label,
    required this.value,
    this.style,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: valueStyle ?? style),
      ],
    );
  }
}

class _DiscountToggleBtn extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _DiscountToggleBtn({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration:
            const Duration(milliseconds: AppDimens.animFast),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.spacingLG,
          vertical: AppDimens.spacingMD,
        ),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        ),
        child: Text(
          label,
          style: AppTypography.labelLarge.copyWith(
            color: isActive ? AppColors.background : AppColors.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PaymentBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final PaymentMethod method;
  final PaymentMethod? selected;
  final VoidCallback onTap;

  const _PaymentBtn({
    required this.label,
    required this.icon,
    required this.method,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == method;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: AppDimens.animFast),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentGlow : AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusLG),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? AppColors.accent : AppColors.textSecondary,
            ),
            const SizedBox(width: AppDimens.spacingSM),
            Text(
              label,
              style: AppTypography.titleMedium.copyWith(
                color: isSelected ? AppColors.accent : AppColors.textPrimary,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderSuccessSheet extends StatelessWidget {
  final VoidCallback onNewOrder;
  final VoidCallback onPrint;

  const _OrderSuccessSheet({
    required this.onNewOrder,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppDimens.radiusXXL),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppDimens.spacingXXL,
        AppDimens.spacingXXL,
        AppDimens.spacingXXL,
        MediaQuery.of(context).padding.bottom + AppDimens.spacingXXL,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Success icon
          const SizedBox(
            width: 80,
            height: 80,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.successDim,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                color: AppColors.success,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: AppDimens.spacingXL),
          Text(
            AppStrings.orderSuccess,
            style: AppTypography.headlineMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimens.spacingXS),
          Text(
            'Payment received successfully',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDimens.spacing3XL),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPrint,
                  icon: const Icon(Icons.print_outlined,
                      size: 18, color: AppColors.textSecondary),
                  label: Text(
                    AppStrings.printReceipt,
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppDimens.spacingLG),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimens.radiusMD),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppDimens.spacingMD),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onNewOrder,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    AppStrings.newOrder,
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.background,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(
                        vertical: AppDimens.spacingLG),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimens.radiusMD),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// extension removed — use AppDimens.spacingXL directly
