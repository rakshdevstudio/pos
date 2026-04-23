import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/constants/constants.dart';
import '../shared/widgets/illume_button.dart';

class UpiScreen extends StatefulWidget {
  final double total;
  final String upiId;

  const UpiScreen({
    super.key,
    required this.total,
    this.upiId = 'illume@upi', // Replace with actual UPI ID
  });

  @override
  State<UpiScreen> createState() => _UpiScreenState();
}

class _UpiScreenState extends State<UpiScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  bool _paymentConfirmed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String get _upiString =>
      'upi://pay?pa=${widget.upiId}&pn=Illume&am=${widget.total.toStringAsFixed(2)}&cu=INR';

  void _markAsPaid() {
    setState(() => _paymentConfirmed = true);
    _pulseController.stop();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              height: AppDimens.appBarHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.spacingXXL,
              ),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    AppStrings.upi,
                    style: AppTypography.headlineSmall.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // QR content
            Expanded(
              child: Center(
                child: _paymentConfirmed
                    ? _buildSuccessState()
                    : _buildQRState(),
              ),
            ),

            // Bottom actions
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppDimens.spacingXXL,
                AppDimens.spacingMD,
                AppDimens.spacingXXL,
                MediaQuery.of(context).padding.bottom + AppDimens.spacingXXL,
              ),
              child: Column(
                children: [
                  IllumeButton(
                    label: AppStrings.markAsPaid,
                    onPressed: _paymentConfirmed ? null : _markAsPaid,
                    icon: Icons.check_circle_outline_rounded,
                  ),
                  const SizedBox(height: AppDimens.spacingMD),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(
                      'Cancel Payment',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQRState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppStrings.scanToPayUpi,
          style: AppTypography.headlineSmall.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDimens.spacingXS),
        Text(
          AppStrings.waitingForPayment,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: AppDimens.spacing4XL),

        // QR Code
        ScaleTransition(
          scale: _pulseAnim,
          child: Container(
            padding: const EdgeInsets.all(AppDimens.spacingXXL),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppDimens.radiusXXL),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  blurRadius: 40,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: QrImageView(
              data: _upiString,
              version: QrVersions.auto,
              size: 240,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF0B0B0B),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0B0B0B),
              ),
            ),
          ),
        ),

        const SizedBox(height: AppDimens.spacing3XL),

        // Amount
        Text(
          '₹${widget.total.toStringAsFixed(2)}',
          style: AppTypography.monoPrice.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDimens.spacingXS),
        Text(
          widget.upiId,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: AppDimens.spacingXXL),

        // Waiting indicator
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: AppDimens.spacingSM),
            Text(
              AppStrings.waitingForPayment,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuccessState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: const BoxDecoration(
            color: AppColors.successDim,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: AppColors.success,
            size: 52,
          ),
        ),
        const SizedBox(height: AppDimens.spacingXXL),
        Text(
          AppStrings.paymentConfirmed,
          style: AppTypography.headlineMedium.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppDimens.spacingXS),
        Text(
          '₹${widget.total.toStringAsFixed(2)} received via UPI',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
