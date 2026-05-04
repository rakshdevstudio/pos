import 'package:flutter/material.dart';
import '../../core/constants/constants.dart';

class NumpadSheet extends StatefulWidget {
  final int initialValue;
  final String title;

  const NumpadSheet({
    super.key,
    required this.initialValue,
    required this.title,
  });

  @override
  State<NumpadSheet> createState() => _NumpadSheetState();
}

class _NumpadSheetState extends State<NumpadSheet> {
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue.toString();
  }

  void _onKey(String key) {
    setState(() {
      if (key == 'C') {
        _value = '0';
      } else if (key == 'SAVE') {
        // Handled directly inside keypad builder now via onKey hook check
      } else if (key == '<') {
        if (_value.length > 1) {
          _value = _value.substring(0, _value.length - 1);
        } else {
          _value = '0';
        }
      } else {
        if (_value == '0') {
          _value = key;
        } else if (_value.length < 4) {
          _value += key;
        }
      }
    });
  }

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title.toUpperCase(),
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 1,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon:
                    const Icon(Icons.close_rounded, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.spacingXL),
          Text(
            _value,
            style: AppTypography.monoPrice.copyWith(
              color: AppColors.textPrimary,
              fontSize: 48,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppDimens.spacing3XL),
          _buildKeypad(context),
        ],
      ),
    );
  }

  Widget _buildKeypad(BuildContext context) {
    return Column(
      children: [
        _buildRow(context, ['1', '2', '3']),
        const SizedBox(height: AppDimens.spacingMD),
        _buildRow(context, ['4', '5', '6']),
        const SizedBox(height: AppDimens.spacingMD),
        _buildRow(context, ['7', '8', '9']),
        const SizedBox(height: AppDimens.spacingMD),
        _buildRow(context, ['C', '0', 'SAVE']),
      ],
    );
  }

  Widget _buildRow(BuildContext context, List<String> keys) {
    return Row(
      children: keys.map((key) {
        return Expanded(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppDimens.spacingSM),
            child: GestureDetector(
              onTap: () {
                if (key == 'SAVE') {
                  Navigator.pop(context, int.tryParse(_value) ?? 0);
                } else {
                  _onKey(key);
                }
              },
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color:
                      key == 'SAVE' ? AppColors.accent : AppColors.background,
                  borderRadius: BorderRadius.circular(AppDimens.radiusLG),
                  border: key == 'SAVE'
                      ? null
                      : Border.all(color: AppColors.border),
                ),
                alignment: Alignment.center,
                child: key == 'SAVE'
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.background)
                    : key == '<'
                        ? const Icon(Icons.backspace_outlined,
                            color: AppColors.textPrimary)
                        : Text(
                            key,
                            style: AppTypography.titleLarge.copyWith(
                              color: key == 'C'
                                  ? AppColors.error
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 24,
                            ),
                          ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
