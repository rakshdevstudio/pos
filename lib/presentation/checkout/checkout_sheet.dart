import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/constants.dart';
import '../../core/providers/providers.dart';
import '../../domain/models/models.dart';
import '../../services/cart_service.dart';
import '../../services/print_service.dart';
import '../../services/sync_service.dart';
import '../shared/widgets/illume_button.dart';
import 'upi_screen.dart';

final _currencyFmt = NumberFormat('#,##0', 'en_IN');

class CheckoutSheet extends ConsumerStatefulWidget {
  final CustomerInfo customer;

  const CheckoutSheet({super.key, required this.customer});

  @override
  ConsumerState<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<CheckoutSheet> {
  final _discountController = TextEditingController();
  final _cashController = TextEditingController();
  final _upiController = TextEditingController();
  final _cardController = TextEditingController();

  PaymentMethod? _selectedPayment;
  bool _isPercentDiscount = false;
  bool _isPlacing = false;

  @override
  void initState() {
    super.initState();
    final cart = ref.read(cartProvider);
    _discountController.text =
        cart.discountValue > 0 ? _trimAmount(cart.discountValue) : '';
    _isPercentDiscount = cart.isPercentDiscount;
    _loadLastPayment();
  }

  @override
  void dispose() {
    _discountController.dispose();
    _cashController.dispose();
    _upiController.dispose();
    _cardController.dispose();
    super.dispose();
  }

  Future<void> _loadLastPayment() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString('last_payment_method');
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedPayment = last == null
          ? PaymentMethod.cash
          : PaymentMethod.values.firstWhere(
              (method) => method.name == last,
              orElse: () => PaymentMethod.cash,
            );
    });
  }

  void _applyDiscount(String value) {
    ref.read(cartProvider.notifier).setDiscount(
          value: double.tryParse(value.trim()) ?? 0,
          isPercent: _isPercentDiscount,
        );
  }

  Future<void> _placeOrder() async {
    final cart = ref.read(cartProvider);
    final paymentMethod = _selectedPayment;
    if (paymentMethod == null) {
      _showSnack(
        'Please select a payment method',
        backgroundColor: AppColors.errorDim,
      );
      return;
    }

    final paymentBreakdown = _resolvePaymentBreakdown(cart.total);
    if (paymentBreakdown == null) {
      return;
    }

    if (paymentMethod == PaymentMethod.upi) {
      final paid = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => UpiScreen(total: cart.total),
        ),
      );
      if (paid != true) {
        return;
      }
    }

    await _finalizeOrder(
      paymentMethod: paymentMethod,
      paymentBreakdown: paymentBreakdown,
    );
  }

  List<PaymentAllocation>? _resolvePaymentBreakdown(double total) {
    final paymentMethod = _selectedPayment;
    if (paymentMethod == null) {
      return null;
    }

    if (paymentMethod != PaymentMethod.split) {
      return [
        PaymentAllocation(method: paymentMethod, amount: total),
      ];
    }

    final entries = <PaymentAllocation>[
      PaymentAllocation(
        method: PaymentMethod.cash,
        amount: _parseAmount(_cashController.text),
      ),
      PaymentAllocation(
        method: PaymentMethod.upi,
        amount: _parseAmount(_upiController.text),
      ),
      PaymentAllocation(
        method: PaymentMethod.card,
        amount: _parseAmount(_cardController.text),
      ),
    ].where((entry) => entry.amount > 0).toList();

    if (entries.isEmpty) {
      _showSnack(
        'Enter the payment breakup for mixed payment',
        backgroundColor: AppColors.errorDim,
      );
      return null;
    }

    final totalPaid =
        entries.fold<double>(0, (sum, entry) => sum + entry.amount);
    if ((totalPaid - total).abs() > 0.5) {
      _showSnack(
        'Mixed payment must equal ₹${_currencyFmt.format(total)}',
        backgroundColor: AppColors.errorDim,
      );
      return null;
    }

    return entries;
  }

  Future<void> _finalizeOrder({
    required PaymentMethod paymentMethod,
    required List<PaymentAllocation> paymentBreakdown,
  }) async {
    final cart = ref.read(cartProvider);
    final repo = ref.read(orderRepoProvider);

    final stockIssue = cart.items.where((item) =>
        item.variant.stock <= 0 || item.quantity > item.variant.stock);
    if (stockIssue.isNotEmpty) {
      _showSnack(
        'Out of stock for one or more items',
        backgroundColor: AppColors.errorDim,
      );
      return;
    }

    setState(() {
      _isPlacing = true;
    });
    HapticFeedback.mediumImpact();

    Order? pendingOrder;
    var savedLocally = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_payment_method', paymentMethod.name);
      final schoolId = prefs.getString('selectedSchoolId') ?? '';
      final schoolName = prefs.getString('selectedSchoolName') ?? 'Store';
      final branchId = prefs.getString('selectedBranchId') ?? '';
      if (schoolId.isEmpty || branchId.isEmpty) {
        throw StateError('School selection is missing');
      }

      pendingOrder = Order(
        offlineId: const Uuid().v4(),
        customer: widget.customer,
        schoolId: schoolId,
        items: cart.items,
        subtotal: cart.subtotal,
        discountAmount: cart.discountAmount,
        total: cart.total,
        paymentMethod: paymentMethod,
        paymentBreakdown: paymentBreakdown,
        metadata: {
          ..._buildOrderMetadata(
            cart: cart,
            paymentMethod: paymentMethod,
            paymentBreakdown: paymentBreakdown,
          ),
          'branch_id': branchId,
          'school_name': schoolName,
        },
        createdAt: DateTime.now(),
      );

      final newCount = await repo.saveOrderLocally(pendingOrder);
      savedLocally = true;
      ref.read(pendingOrdersCountProvider.notifier).setCount(newCount);

      var syncPending = false;
      try {
        await repo.applyInventoryMovements(
          items: cart.items,
          branchId: branchId,
          schoolId: schoolId,
          schoolName: schoolName,
          customerName: _customerNameForOrder(widget.customer),
          subtotal: cart.subtotal,
          discountAmount: cart.discountAmount,
          total: cart.total,
          paymentMethod: paymentMethod,
          paymentBreakdown: paymentBreakdown,
          metadata: pendingOrder.metadata,
          customerPhone: _trimToNull(widget.customer.phone),
          alternatePhone: _trimToNull(widget.customer.alternatePhone),
          customerEmail: null,
          customerAddress: _trimToNull(widget.customer.address) ?? '-',
          city: _trimToNull(widget.customer.city),
          pincode: _trimToNull(widget.customer.pincode),
          studentName: _trimToNull(widget.customer.studentName),
          grade: _trimToNull(widget.customer.grade) ??
              _trimToNull(widget.customer.studentClass),
          className: _trimToNull(widget.customer.className) ??
              _trimToNull(widget.customer.studentClass),
          source: 'pos',
          orderChannel: 'offline',
          customerType: 'walk_in',
          status: 'Placed',
          orderId: pendingOrder.offlineId,
        );
      } catch (error) {
        syncPending = true;
        debugPrint(
          'POS CHECKOUT WARN: remote stock sync failed, keeping order pending. $error',
        );
        await ref.read(syncProvider.notifier).syncPendingOrders();
        final offlineId = pendingOrder.offlineId;
        final stillPending = (await repo.getPendingOrders())
            .any((order) => order.offlineId == offlineId);
        syncPending = stillPending;
      }

      ref.read(syncProvider.notifier).syncPendingOrders();
      ref.read(cartProvider.notifier).processCheckout();
      HapticFeedback.heavyImpact();

      if (mounted) {
        if (syncPending) {
          _showSnack(
            'Order saved locally. Stock sync is pending.',
            backgroundColor: AppColors.surfaceElevated,
          );
        }
        _showSuccessSheet(order: pendingOrder, syncPending: syncPending);
      }
    } catch (error) {
      if (mounted) {
        _showSnack(
          savedLocally
              ? 'Order saved locally, but checkout could not finish cleanly.'
              : 'Could not place order.',
          backgroundColor: AppColors.errorDim,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPlacing = false;
        });
      }
    }
  }

  Map<String, dynamic> _buildOrderMetadata({
    required CartState cart,
    required PaymentMethod paymentMethod,
    required List<PaymentAllocation> paymentBreakdown,
  }) {
    return {
      'payment_label':
          paymentMethod == PaymentMethod.split ? 'Mixed' : paymentMethod.label,
      'payment_summary': _paymentSummary(paymentBreakdown),
      'item_count': cart.itemCount,
      'discount_value': cart.discountValue,
      'is_percent_discount': cart.isPercentDiscount,
      'customer_name': _customerNameForOrder(widget.customer),
      'receipt_items': cart.items
          .map(
            (item) => {
              'name': item.product.name,
              'size': item.variant.size,
              'qty': item.quantity,
              'price': item.variant.price,
              'line_total': item.lineTotal,
            },
          )
          .toList(),
    };
  }

  String _paymentSummary(List<PaymentAllocation> paymentBreakdown) {
    return paymentBreakdown
        .map(
          (entry) =>
              '${entry.method.label} ₹${_currencyFmt.format(entry.amount)}',
        )
        .join(' + ');
  }

  String _customerNameForOrder(CustomerInfo customer) {
    final enteredName = _trimToNull(customer.name);
    if (enteredName != null) {
      return enteredName;
    }

    final enteredStudentName = _trimToNull(customer.studentName);
    if (enteredStudentName != null) {
      return enteredStudentName;
    }

    return 'Walk-in Customer';
  }

  String? _trimToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  double _parseAmount(String value) {
    return double.tryParse(value.trim()) ?? 0;
  }

  String _trimAmount(double value) {
    final isWhole = value == value.roundToDouble();
    return isWhole ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  void _showSnack(
    String message, {
    Color backgroundColor = AppColors.surfaceElevated,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSheet({
    required Order order,
    bool syncPending = false,
  }) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderSuccessSheet(
        order: order,
        syncPending: syncPending,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final splitTotal = _parseAmount(_cashController.text) +
        _parseAmount(_upiController.text) +
        _parseAmount(_cardController.text);
    final splitRemaining = cart.total - splitTotal;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppDimens.spacingXXL,
        AppDimens.spacingXXL,
        AppDimens.spacingXXL,
        MediaQuery.of(context).padding.bottom + AppDimens.spacingXXL,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Checkout',
              style: AppTypography.headlineMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppDimens.spacingXS),
            Text(
              '${cart.itemCount} items • ₹${_currencyFmt.format(cart.total)} payable',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppDimens.spacingXXL),
            _BillSummary(cart: cart),
            const SizedBox(height: AppDimens.spacingXXL),
            _buildDiscountSection(cart),
            const SizedBox(height: AppDimens.spacingXXL),
            _buildPaymentSection(),
            if (_selectedPayment == PaymentMethod.split) ...[
              const SizedBox(height: AppDimens.spacingXL),
              _buildSplitPaymentSection(splitRemaining),
            ],
            const SizedBox(height: AppDimens.spacingXXL),
            _buildFooter(cart),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountSection(CartState cart) {
    return Container(
      padding: const EdgeInsets.all(AppDimens.spacingLG),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Discount',
            style: AppTypography.titleLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppDimens.spacingMD),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _discountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Discount value',
                    suffixText: _isPercentDiscount ? '%' : '₹',
                  ),
                  onChanged: _applyDiscount,
                ),
              ),
              const SizedBox(width: AppDimens.spacingMD),
              ChoiceChip(
                label: const Text('%'),
                selected: _isPercentDiscount,
                onSelected: (_) {
                  setState(() {
                    _isPercentDiscount = true;
                  });
                  _applyDiscount(_discountController.text);
                },
              ),
              const SizedBox(width: AppDimens.spacingSM),
              ChoiceChip(
                label: const Text('₹'),
                selected: !_isPercentDiscount,
                onSelected: (_) {
                  setState(() {
                    _isPercentDiscount = false;
                  });
                  _applyDiscount(_discountController.text);
                },
              ),
            ],
          ),
          if (cart.discountAmount > 0) ...[
            const SizedBox(height: AppDimens.spacingSM),
            Text(
              'Discount applied: ₹${_currencyFmt.format(cart.discountAmount)}',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentSection() {
    return Container(
      padding: const EdgeInsets.all(AppDimens.spacingLG),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payment Mode',
            style: AppTypography.titleLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppDimens.spacingMD),
          Wrap(
            spacing: AppDimens.spacingSM,
            runSpacing: AppDimens.spacingSM,
            children: PaymentMethod.values
                .map(
                  (method) => ChoiceChip(
                    label: Text(method.label.toUpperCase()),
                    selected: _selectedPayment == method,
                    onSelected: (_) {
                      setState(() {
                        _selectedPayment = method;
                      });
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitPaymentSection(double splitRemaining) {
    return Container(
      padding: const EdgeInsets.all(AppDimens.spacingLG),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mixed Payment Breakup',
            style: AppTypography.titleLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppDimens.spacingXS),
          Text(
            'Example: ₹500 cash + ₹250 UPI',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: AppDimens.spacingLG),
          _PaymentAmountField(
            controller: _cashController,
            label: 'Cash',
            icon: Icons.payments_outlined,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppDimens.spacingMD),
          _PaymentAmountField(
            controller: _upiController,
            label: 'UPI',
            icon: Icons.qr_code_rounded,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppDimens.spacingMD),
          _PaymentAmountField(
            controller: _cardController,
            label: 'Card',
            icon: Icons.credit_card_rounded,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppDimens.spacingMD),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Remaining',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '₹${_currencyFmt.format(splitRemaining.abs())}'
                '${splitRemaining < 0 ? ' over' : ''}',
                style: AppTypography.titleMedium.copyWith(
                  color: splitRemaining.abs() <= 0.5
                      ? AppColors.success
                      : AppColors.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(CartState cart) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Subtotal',
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
        if (cart.discountAmount > 0) ...[
          const SizedBox(height: AppDimens.spacingXS),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Discount',
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
        ],
        const SizedBox(height: AppDimens.spacingMD),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total',
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '₹${_currencyFmt.format(cart.total)}',
              style: AppTypography.headlineMedium.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.spacingXL),
        IllumeButton(
          label: 'CONFIRM PAYMENT',
          icon: Icons.check_circle_rounded,
          isLoading: _isPlacing,
          onPressed: _selectedPayment == null ? null : _placeOrder,
        ),
      ],
    );
  }
}

class _BillSummary extends StatelessWidget {
  final CartState cart;

  const _BillSummary({required this.cart});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
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
        itemBuilder: (_, index) {
          final item = cart.items[index];
          return ListTile(
            dense: true,
            title: Text(
              item.product.name,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Size ${item.variant.size} × ${item.quantity}',
              style: AppTypography.bodySmall.copyWith(
                color: item.variant.stock <= PosConstants.lowStockThreshold
                    ? AppColors.warning
                    : AppColors.textMuted,
              ),
            ),
            trailing: Text(
              '₹${_currencyFmt.format(item.lineTotal)}',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PaymentAmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final ValueChanged<String> onChanged;

  const _PaymentAmountField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: '$label amount',
        prefixIcon: Icon(icon),
        prefixText: '₹ ',
      ),
    );
  }
}

class _OrderSuccessSheet extends StatelessWidget {
  final Order order;
  final bool syncPending;

  const _OrderSuccessSheet({
    required this.order,
    this.syncPending = false,
  });

  @override
  Widget build(BuildContext context) {
    final paymentSummary = order.resolvedPaymentBreakdown
        .map(
          (entry) =>
              '${entry.method.label} ₹${_currencyFmt.format(entry.amount)}',
        )
        .join(' + ');
    final mediaQuery = MediaQuery.of(context);
    final maxSheetHeight = mediaQuery.size.height * 0.86;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppDimens.spacingXXL,
        AppDimens.spacingXXL,
        AppDimens.spacingXXL,
        mediaQuery.padding.bottom + AppDimens.spacingXXL,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 42,
                  ),
                  const SizedBox(width: AppDimens.spacingMD),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          syncPending
                              ? 'Order saved locally'
                              : 'Order placed successfully',
                          style: AppTypography.headlineSmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppDimens.spacingXXS),
                        Text(
                          syncPending
                              ? '${order.offlineId} • Sync pending'
                              : order.offlineId,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.spacingXL),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppDimens.spacingLG),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppDimens.radiusLG),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Amount: ₹${_currencyFmt.format(order.total)}',
                      style: AppTypography.titleLarge.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppDimens.spacingSM),
                    Text(
                      'Items: ${order.items.length} products • ${order.items.fold<int>(0, (sum, item) => sum + item.quantity)} pcs',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppDimens.spacingXS),
                    Text(
                      'Payment: $paymentSummary',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (syncPending) ...[
                      const SizedBox(height: AppDimens.spacingXS),
                      Text(
                        AppStrings.syncPending,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppDimens.spacingLG),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: order.items.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (_, index) {
                    final item = order.items[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        item.product.name,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Size ${item.variant.size} × ${item.quantity}',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                      trailing: Text(
                        '₹${_currencyFmt.format(item.lineTotal)}',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppDimens.spacingLG),
              IllumeButton(
                label: 'PRINT RECEIPT',
                icon: Icons.print_rounded,
                onPressed: () async {
                  final printed = await printService.printReceipt(order);
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        printed
                            ? 'Receipt sent to printer'
                            : 'Printer not available',
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppDimens.spacingMD),
              IllumeButton(
                label: 'NEW BILL',
                icon: Icons.add_shopping_cart_rounded,
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
              const SizedBox(height: AppDimens.spacingSM),
              TextButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('WhatsApp receipt will be added soon'),
                    ),
                  );
                },
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share WhatsApp Receipt'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
