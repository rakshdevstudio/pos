import re

with open('lib/presentation/pos/pos_screen.dart', 'r') as f:
    content = f.read()

# 1. Add processBarcodeScan and modify _handleBarcodeSubmit
process_func = """
  Future<void> processBarcodeScan(String rawCode) async {
    debugPrint("RAW SCANNER VALUE: [$rawCode]");
    
    var code = rawCode.replaceAll(RegExp(r'[\\r\\n\\t\\u200B\\u200C\\u200D\\uFEFF]+'), '');
    code = code.trim();
    
    debugPrint("NORMALIZED VALUE: [$code]");
    debugPrint("CALLING EXISTING LOOKUP: [$code]");
    
    _handleBarcodeSubmit(code);
  }

  void _handleBarcodeSubmit(String normalizedCode) {
    if (normalizedCode.isEmpty) {
      _focusBarcodeField();
      return;
    }
"""

content = re.sub(
    r'  void _handleBarcodeSubmit\(String rawCode\) \{\n    final normalizedCode =\n        ref\.read\(barcodeLookupServiceProvider\)\.normalizeBarcode\(rawCode\);\n    if \(normalizedCode == null\) \{\n      _focusBarcodeField\(\);\n      return;\n    \}',
    process_func,
    content
)

# 2. Update _handleScannerInput to call processBarcodeScan
scanner_input_old = """      if (event.logicalKey == LogicalKeyboardKey.enter) {
        final barcode = _globalScannerBuffer.toString().trim();
        debugPrint('SCANNER ENTER RECEIVED:');

        if (barcode.isNotEmpty) {
          debugPrint('SUBMITTING BARCODE: $barcode');
          _handleBarcodeSubmit(barcode);
        }

        _globalScannerBuffer.clear();

        // Immediately request focus back
        scannerFocusNode.requestFocus();
      }"""

scanner_input_new = """      if (event.logicalKey == LogicalKeyboardKey.enter) {
        final rawCode = _globalScannerBuffer.toString();
        _globalScannerBuffer.clear();
        scannerFocusNode.requestFocus();

        if (rawCode.trim().isNotEmpty) {
          unawaited(processBarcodeScan(rawCode));
        }
      }"""

content = content.replace(scanner_input_old, scanner_input_new)

# 3. Update SearchField onSubmitted
content = content.replace('onSubmitted: _handleBarcodeSubmit,', 'onSubmitted: processBarcodeScan,')

# 4. Add debug logs in _processBarcodeScan
content = content.replace("      if (match == null) {\n        _showBarcodeSnackBar(", "      if (match == null) {\n        debugPrint('NO PRODUCT FOUND: [$barcode]');\n        _showBarcodeSnackBar(")

content = content.replace("      final addResult = ref\n          .read(cartProvider.notifier)\n          .addItemWithResult(match.product, match.variant);", "      debugPrint('FOUND PRODUCT: ${match.product.name} - ${match.variant.name}');\n      final addResult = ref\n          .read(cartProvider.notifier)\n          .addItemWithResult(match.product, match.variant);")

with open('lib/presentation/pos/pos_screen.dart', 'w') as f:
    f.write(content)
