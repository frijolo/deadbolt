import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:deadbolt/src/rust/api/analyzer.dart';
import 'package:deadbolt/src/rust/frb_generated.dart';

void main() {
  setUpAll(() async {
    await RustLib.init();
  });
  
  test('pkh descriptor analysis', () async {
    const desc = "pkh([73c5da0a/44h/1h/0h]tpubDC5FSnBiZDMmhiuCmWAYsLwgLYrrT9rAqvTySfuCCrgsWz8wxMXUS9Tb9iVMvcRbvFcAHGkMD5Kx8koh4GquNGNTfohfk7pgjhaPCdXpoba/<0;1>/*)#0x5u8d5c";
    final result = await analyzeDescriptor(descriptor: desc);
    debugPrint("Keys: ${result.keys.length}");
    expect(result.keys, isNotEmpty);
  });
}
