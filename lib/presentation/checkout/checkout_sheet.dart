import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/constants.dart';
import '../../core/providers/providers.dart';
import '../../domain/models/models.dart';
import '../../services/cart_service.dart';
import '../../services/sync_service.dart';
import '../shared/widgets/illume_button.dart';
import 'upi_screen.dart';

final _currencyFmt = NumberFormat('#,##0', 'en_IN');
final _discountValueProvider = StateProvider<double>((ref) => 0);
final _isPercentDiscountProvider = StateProvider<bool>((ref) => false);
final _selectedPaymentProvider = StateProvider<PaymentMethod?>((ref) => null);
final _orderPlacingProvider = StateProvider<bool>((ref) => false);

class CheckoutSheet extends ConsumerStatefulWidget {
  final CustomerInfo customer;
  const CheckoutSheet({super.key, required this.customer});

  @override
  ConsumerState<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<CheckoutSheet> {
  final _discountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLastPayment();
  }

  @override
  void dispose() {
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _loadLastPayment() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString('last_payment_method');
    if (last != null && mounted) {
      final method = PaymentMethod.values.firstWhere(
        (e) => e.name == last,
        orElse: () => PaymentMethod.cash,
      );
      ref.read(_selectedPaymentProvider.notifier).state = method;
    }
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
      final paid = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => UpiScreen(total: cart.total),
        ),
      );
      if (paid == true) {
        await _finalizeOrder();
      }
      return;
    }

    await _finalizeOrder();
  }

  Future<void> _finalizeOrder({double? tenderedAmount}) async {
    final cart = ref.read(cartProvider);
    final payment = ref.read(_selectedPaymentProvider) ?? PaymentMethod.cash;

    final stockIssue = cart.items.where((item) =>
        item.variant.stock <= 0 || item.quantity > item.variant.stock);
    if (stockIssue.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Out of stock for one or more items'),
          backgroundColor: AppColors.errorDim,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (tenderedAmount != null && tenderedAmount < cart.total) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Insufficient payment amount'),
          backgroundColor: AppColors.errorDim,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    ref.read(_orderPlacingProvider.notifier).state = true;
    HapticFeedback.mediumImpact();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_payment_method', payment.name);
      final schoolId = prefs.getString('selectedSchoolId') ?? '';
      final branchId = prefs.getString('selectedBranchId') ?? '';
      if (schoolId.isEmpty || branchId.isEmpty) {
        throw StateError('School selection is missing');
      }

      final order = Order(
        offlineId: const Uuid().v4(),
        customer: widget.customer,
        schoolId: schoolId,
        items: cart.items,
        subtotal: cart.subtotal,
        discountAmount: cart.discountAmount,
        total: cart.total,
        paymentMethod: payment,
        createdAt: DateTime.now(),
      );

      // Use provider singleton — no direct instantiation
      final repo = ref.read(orderRepoProvider);
      await repo.applyInventoryMovements(
        items: cart.items,
        branchId: branchId,
      );
      final newCount = await repo.saveOrderLocally(order);
      ref.read(pendingOrdersCountProvider.notifier).setCount(newCount);

      // Non-blocking sync attempt
      ref.read(syncProvider.notifier).syncPendingOrders();

      ref.read(cartProvider.notifier).processCheckout();
      HapticFeedback.heavyImpact();

      if (mounted) {
        _showSuccessSheet(total: cart.total, tenderedAmount: tenderedAmount);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update stock. Order was not placed.'),
            backgroundColor: AppColors.errorDim,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        ref.read(_orderPlacingProvider.notifier).state = false;
      }
    }
  }

  void _showSuccessSheet({required double total, double? tenderedAmount}) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderSuccessSheet(
        total: total,
        tendered: tenderedAmount,
        onNewOrder: () {
          Navigator.of(context).popUntil((r) => r.isFirst);
        },
        onPrint: () async {
          Navigator.pop(context);
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Receipt sent to printer')),
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

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppDimens.radiusXXL)),
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
          _buildBillSummary(cart),
          const SizedBox(height: AppDimens.spacingXXL),
          _buildDiscountSection(isPercent),
          const SizedBox(height: AppDimens.spacingXXL),
          _buildFinalTotal(cart),
          const SizedBox(height: AppDimens.spacingXXL),
          _buildPaymentSection(selectedPayment),
          const SizedBox(height: AppDimens.spacing3XL),
          IllumeButton(
            label: selectedPayment == PaymentMethod.cash
                ? 'COMPLETE PAYMENT'
                : 'CONFIRM PAYMENT',
            onPressed: selectedPayment == null ? null : _placeOrder,
            isLoading: isPlacing,
            icon: Icons.check_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildBillSummary(CartState cart) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BILL SUMMARY',
            style: AppTypography.titleLarge
                .copyWith(color: AppColors.textSecondary, letterSpacing: 2)),
        const SizedBox(height: AppDimens.spacingMD),
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppDimens.radiusLG),
            border: Border.all(color: AppColors.border),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: cart.items.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (_, i) {
              final item = cart.items[i];
              return ListTile(
                title: Text(item.product.name),
                subtitle: Text('Size ${item.variant.size} × ${item.quantity}'),
                trailing: Text('₹${_currencyFmt.format(item.lineTotal)}'),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDiscountSection(bool isPercent) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _discountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Discount',
              suffixText: isPercent ? '%' : '₹',
              filled: true,
              fillColor: AppColors.surface,
            ),
            onChanged: (val) {
              ref.read(_discountValueProvider.notifier).state =
                  double.tryParse(val) ?? 0;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFinalTotal(CartState cart) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('TOTAL', style: AppTypography.titleLarge),
        Text('₹${_currencyFmt.format(cart.total)}',
            style:
                AppTypography.headlineMedium.copyWith(color: AppColors.accent)),
      ],
    );
  }

  Widget _buildPaymentSection(PaymentMethod? selected) {
    return Wrap(
      spacing: 8,
      children: PaymentMethod.values
          .map((m) => ChoiceChip(
                label: Text(m.name.toUpperCase()),
                selected: selected == m,
                onSelected: (_) =>
                    ref.read(_selectedPaymentProvider.notifier).state = m,
              ))
          .toList(),
    );
  }
}

class _OrderSuccessSheet extends StatelessWidget {
  final double total;
  final double? tendered;
  final VoidCallback onNewOrder;
  final VoidCallback onPrint;

  const _OrderSuccessSheet(
      {required this.total,
      this.tendered,
      required this.onNewOrder,
      required this.onPrint});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppDimens.radiusXXL)),
      ),
      padding: const EdgeInsets.all(AppDimens.spacingXXL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 64),
          const SizedBox(height: AppDimens.spacingLG),
          Text('PAID ₹${_currencyFmt.format(total)}',
              style: AppTypography.headlineMedium),
          if (tendered != null && tendered! > total)
            Text('RETURN CHANGE: ₹${_currencyFmt.format(tendered! - total)}',
                style:
                    AppTypography.titleLarge.copyWith(color: AppColors.accent)),
          const SizedBox(height: AppDimens.spacingXL),
          IllumeButton(label: 'NEW ORDER', onPressed: onNewOrder),
        ],
      ),
    );
  }
}
