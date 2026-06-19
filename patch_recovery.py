import re

with open('lib/presentation/pos/pos_screen.dart', 'r') as f:
    content = f.read()

# 1. Add hidden scanner controllers
content = re.sub(
    r'  List<HeldBillDraft> _draftBills = const \[\];\n',
    r'  List<HeldBillDraft> _draftBills = const [];\n\n  late final TextEditingController hiddenScannerController;\n  late final FocusNode hiddenScannerFocus;\n',
    content
)

# 2. Add to initState
content = re.sub(
    r'  @override\n  void initState\(\) \{\n    super\.initState\(\);\n',
    r'  @override\n  void initState() {\n    super.initState();\n    hiddenScannerController = TextEditingController();\n    hiddenScannerFocus = FocusNode();\n    WidgetsBinding.instance.addPostFrameCallback((_) {\n      hiddenScannerFocus.requestFocus();\n    });\n',
    content
)

# 3. Add to dispose
content = re.sub(
    r'  @override\n  void dispose\(\) \{\n',
    r'  @override\n  void dispose() {\n    hiddenScannerController.dispose();\n    hiddenScannerFocus.dispose();\n',
    content
)

# 4. Wrap Scaffold body in a Stack
body_pattern = r'        child: Scaffold\(\n          backgroundColor: AppColors\.background,\n          resizeToAvoidBottomInset: false,\n          body: _schoolId == null'

replacement_body = """        child: Scaffold(
          backgroundColor: AppColors.background,
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              // Hidden scanner field
              Opacity(
                opacity: 0,
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: TextField(
                    controller: hiddenScannerController,
                    focusNode: hiddenScannerFocus,
                    autofocus: true,
                    onSubmitted: (value) {
                      debugPrint("HIDDEN SCANNER SUBMIT: $value");
                      _handleBarcodeSubmit(value);
                      hiddenScannerController.clear();
                      hiddenScannerFocus.requestFocus();
                    },
                  ),
                ),
              ),
              // Main content
              Positioned.fill(
                child: _schoolId == null"""

content = re.sub(body_pattern, replacement_body, content)

content = content.replace('          bottomNavigationBar:', '              ),\n            ],\n          ),\n          bottomNavigationBar:')

# 5. Add Focus requests

# In _processBarcodeScan after addToCart success
old_add_cart = """        case CartAddResult.added:
          HapticFeedback.lightImpact();"""
new_add_cart = """        case CartAddResult.added:
          if (mounted) hiddenScannerFocus.requestFocus();
          HapticFeedback.lightImpact();"""
content = content.replace(old_add_cart, new_add_cart)

# In _handleCheckout success
old_checkout = """        if (dialogResult == true && mounted) {
          unawaited(_startCheckout());
        }"""
new_checkout = """        if (dialogResult == true && mounted) {
          hiddenScannerFocus.requestFocus();
          unawaited(_startCheckout());
        } else if (mounted) {
          hiddenScannerFocus.requestFocus();
        }"""
content = content.replace(old_checkout, new_checkout)

# In dialog close
old_dialog_close = """    if (result == true) {
      if (mounted) {
        setState(() {});
      }
    }"""
new_dialog_close = """    if (result == true) {
      if (mounted) {
        setState(() {});
        hiddenScannerFocus.requestFocus();
      }
    } else {
      if (mounted) {
        hiddenScannerFocus.requestFocus();
      }
    }"""
content = content.replace(old_dialog_close, new_dialog_close)


# 6. Debug Logs
old_handle_submit = r'  void _handleBarcodeSubmit\(String rawCode\) \{\n    final normalizedCode =\n        ref\.read\(barcodeLookupServiceProvider\)\.normalizeBarcode\(rawCode\);\n'
new_handle_submit = """  void _handleBarcodeSubmit(String rawCode) {
    debugPrint("HANDLE BARCODE RECEIVED: $rawCode");
    final normalizedCode =
        ref.read(barcodeLookupServiceProvider).normalizeBarcode(rawCode);
"""
content = re.sub(old_handle_submit, new_handle_submit, content)

old_on_submit = r'      onSubmitted: _handleBarcodeSubmit,\n'
new_on_submit = """      onSubmitted: (value) {
        debugPrint("VISIBLE SEARCH SUBMIT: $value");
        _handleBarcodeSubmit(value);
      },
"""
content = re.sub(old_on_submit, new_on_submit, content)

old_found = r'      final addResult = ref\n          \.read\(cartProvider\.notifier\)\n          \.addItemWithResult\(match\.product, match\.variant\);\n'
new_found = """      debugPrint('PRODUCT FOUND: ${match.product.name} - ${match.variant.name}');
      final addResult = ref
          .read(cartProvider.notifier)
          .addItemWithResult(match.product, match.variant);
"""
content = re.sub(old_found, new_found, content)


with open('lib/presentation/pos/pos_screen.dart', 'w') as f:
    f.write(content)
