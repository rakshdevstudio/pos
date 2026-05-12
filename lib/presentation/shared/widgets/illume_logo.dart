import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/constants/constants.dart';

/// ILLUME Logo Widget - Reusable Logo Component
/// Optimized for clean rendering with proper constraints
///
/// Usage:
/// - LogoIcon() for compact icon-only version
/// - LogoHorizontal() for full horizontal branding
/// - LogoMonochrome() for receipt printing

class LogoIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final bool shadow;

  const LogoIcon({
    super.key,
    this.size = 48,
    this.color,
    this.shadow = false,
  });

  @override
  Widget build(BuildContext context) {
    // Use SizedBox to provide fixed dimensions and prevent overflow
    return SizedBox(
      width: size,
      height: size,
      child: Container(
        decoration: shadow
            ? BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (color ?? AppColors.accent).withValues(alpha: 0.2),
                    blurRadius: 16,
                    spreadRadius: 3,
                  ),
                ],
              )
            : null,
        clipBehavior: Clip.none,
        child: SvgPicture.asset(
          'assets/icons/illume_logo_icon.svg',
          fit: BoxFit.contain,
          placeholderBuilder: (_) => Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.1),
              border: Border.all(
                color: AppColors.accent,
                width: 1.5,
              ),
            ),
          ),
          errorBuilder: (context, error, stackTrace) {
            // Fallback: simple circle with accent color
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.1),
                border: Border.all(
                  color: AppColors.accent,
                  width: 1.5,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class LogoHorizontal extends StatelessWidget {
  final double height;
  final bool showSubtitle;
  final EdgeInsets padding;

  const LogoHorizontal({
    super.key,
    this.height = 64,
    this.showSubtitle = true,
    this.padding = const EdgeInsets.symmetric(horizontal: AppDimens.spacingMD),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: SizedBox(
        height: height,
        width: 160,
        child: SvgPicture.asset(
          'assets/icons/illume_logo_horizontal.svg',
          fit: BoxFit.contain,
          placeholderBuilder: (_) => Center(
            child: Text(
              'ILLUME',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.accent,
                letterSpacing: 2,
              ),
            ),
          ),
          errorBuilder: (context, error, stackTrace) {
            // Fallback: text branding
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'ILLUME',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.accent,
                    letterSpacing: 2,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class LogoMonochrome extends StatelessWidget {
  final double size;
  final bool forPrint;

  const LogoMonochrome({
    super.key,
    this.size = 48,
    this.forPrint = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Container(
        color: forPrint ? Colors.white : Colors.transparent,
        clipBehavior: Clip.none,
        child: SvgPicture.asset(
          'assets/icons/illume_logo_monochrome.svg',
          fit: BoxFit.contain,
          placeholderBuilder: (_) => Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.1),
              border: Border.all(
                color: Colors.black,
                width: 1.5,
              ),
            ),
          ),
          errorBuilder: (context, error, stackTrace) {
            // Fallback: simple black circle
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.1),
                border: Border.all(
                  color: Colors.black,
                  width: 1.5,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
