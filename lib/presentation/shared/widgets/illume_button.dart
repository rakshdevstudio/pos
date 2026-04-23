import 'package:flutter/material.dart';
import '../../../core/constants/constants.dart';

class IllumeButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isSecondary;
  final bool isDanger;
  final double? width;
  final double? height;
  final IconData? icon;

  const IllumeButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.isSecondary = false,
    this.isDanger = false,
    this.width,
    this.height,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDanger
        ? AppColors.errorDim
        : isSecondary
            ? AppColors.surfaceElevated
            : AppColors.accent;

    final fg = isDanger || isSecondary
        ? AppColors.textPrimary
        : AppColors.background;

    final border = isSecondary
        ? const BorderSide(color: AppColors.border, width: 1)
        : BorderSide.none;

    return AnimatedContainer(
      duration: const Duration(milliseconds: AppDimens.animFast),
      width: width ?? double.infinity,
      height: height ?? AppDimens.buttonHeight,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMD),
            side: border,
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: AppDimens.spacingLG),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: fg,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: AppDimens.spacingSM),
                  ],
                  Text(
                    label,
                    style: AppTypography.labelLarge.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
