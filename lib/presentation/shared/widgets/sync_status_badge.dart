import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/constants.dart';
import '../../../services/sync_service.dart';

class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: AppDimens.animMedium),
      child: _buildBadge(syncState),
    );
  }

  Widget _buildBadge(SyncState state) {
    switch (state) {
      case SyncState.offline:
        return _badge(
          key: 'offline',
          icon: Icons.cloud_off_rounded,
          label: AppStrings.offline,
          color: AppColors.error,
        );
      case SyncState.syncing:
        return _badge(
          key: 'syncing',
          icon: Icons.sync_rounded,
          label: AppStrings.syncing,
          color: AppColors.warning,
          spin: true,
        );
      case SyncState.done:
        return _badge(
          key: 'done',
          icon: Icons.cloud_done_rounded,
          label: AppStrings.online,
          color: AppColors.success,
        );
      case SyncState.idle:
        return const SizedBox.shrink(key: ValueKey('idle'));
    }
  }

  Widget _badge({
    required String key,
    required IconData icon,
    required String label,
    required Color color,
    bool spin = false,
  }) {
    return Container(
      key: ValueKey(key),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.spacingMD,
        vertical: AppDimens.spacingXS,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          spin
              ? SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: color,
                  ),
                )
              : Icon(icon, size: 12, color: color),
          const SizedBox(width: AppDimens.spacingXS),
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: color,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
