import 'package:deadbolt/src/rust/api/model.dart';

enum WalletTemperature { hot, warm, cold }

bool isInheritancePath(APISpendPath path, {required int minTimelockBlocks}) =>
    (path.relTimelock.timelockType == APIRelativeTimelockType.blocks &&
        path.relTimelock.value >= minTimelockBlocks) ||
    path.absTimelock.value > 0;

bool isSatisfiedPath(APISpendPath path, Set<String> hotKeyMfps) =>
    path.mfps.where(hotKeyMfps.contains).length >= path.threshold;

WalletTemperature computeWalletTemperature({
  required List<APISpendPath> spendPaths,
  required List<APIHotKeyInfo> hotKeys,
  required int minTimelockBlocks,
}) {
  final hotKeyMfps = hotKeys.map((k) => k.mfp).toSet();
  var hasSatisfiedInheritance = false;
  for (final path in spendPaths) {
    if (!isSatisfiedPath(path, hotKeyMfps)) continue;
    if (!isInheritancePath(path, minTimelockBlocks: minTimelockBlocks)) {
      return WalletTemperature.hot;
    }
    hasSatisfiedInheritance = true;
  }
  return hasSatisfiedInheritance ? WalletTemperature.warm : WalletTemperature.cold;
}
