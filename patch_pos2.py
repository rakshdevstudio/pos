import re

with open('lib/presentation/pos/pos_screen.dart', 'r') as f:
    content = f.read()

# Replace _handleScannerInput logicalKey enter branch
# We want to change the part inside `if (event.logicalKey == LogicalKeyboardKey.enter) { ... }`

old_scanner_input = """      if (event.logicalKey == LogicalKeyboardKey.enter) {
        final barcode = _globalScannerBuffer.toString().trim();
        debugPrint('SCANNER ENTER RECEIVED:');

        if (barcode.isNotEmpty) {
          debugPrint('SUBMITTING BARCODE: $barcode');
          _handleBarcodeSubmit(barcode);
        }

        _globalScannerBuffer.clear();
        scannerFocusNode.requestFocus();
      }"""

new_scanner_input = """      if (event.logicalKey == LogicalKeyboardKey.enter) {
        final rawCode = _globalScannerBuffer.toString();
        _globalScannerBuffer.clear();
        scannerFocusNode.requestFocus();
        
        if (rawCode.trim().isNotEmpty) {
          unawaited(processBarcodeScan(rawCode));
        }
      }"""

content = content.replace(old_scanner_input, new_scanner_input)

# Find onSubmitted: _handleBarcodeSubmit and replace with onSubmitted: processBarcodeScan
content = content.replace('onSubmitted: _handleBarcodeSubmit,', 'onSubmitted: processBarcodeScan,')

# Add processBarcodeScan somewhere
process_barcode_func = """
  Future<void> processBarcodeScan(String rawCode) async {
    debugPrint("RAW SCANNER VALUE: [$rawCode]");
    
    // Allowed cleanup only: .trim(), remove \r, \n, \t, zero width spaces
    var code = rawCode.replaceAll(RegExp(r'[\\r\\n\\t\\u200B\\u200C\\u200D\\uFEFF]+'), '');
    code = code.trim();
    
    debugPrint("NORMALIZED VALUE: [$code]");
    debugPrint("CALLING EXISTING LOOKUP: [$code]");
    
    _handleBarcodeSubmit(code);
  }
"""

# Insert it before _handleBarcodeSubmit
content = content.replace('  void _handleBarcodeSubmit(String rawCode) {', process_barcode_func + '\n  void _handleBarcodeSubmit(String rawCode) {')

with open('lib/presentation/pos/pos_screen.dart', 'w') as f:
    f.write(content)
