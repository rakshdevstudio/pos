import 'package:flutter/material.dart';
import '../../../core/constants/constants.dart';

class IllumeTextField extends StatelessWidget {
  final String? hintText;
  final String? labelText;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool readOnly;

  const IllumeTextField({
    super.key,
    this.hintText,
    this.labelText,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.focusNode,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.autofocus = false,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      focusNode: focusNode,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      textInputAction: textInputAction,
      autofocus: autofocus,
      readOnly: readOnly,
      style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon != null
            ? Padding(
                padding: const EdgeInsets.only(
                  left: AppDimens.spacingLG,
                  right: AppDimens.spacingSM,
                ),
                child: prefixIcon,
              )
            : null,
        prefixIconConstraints: const BoxConstraints(),
        suffixIcon: suffixIcon,
      ),
    );
  }
}
