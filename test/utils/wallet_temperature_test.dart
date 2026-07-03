import 'package:flutter_test/flutter_test.dart';

import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/wallet_temperature.dart';

APIHotKeyInfo _hotKey(String mfp) => APIHotKeyInfo(
      mfp: mfp,
      seedType: 'mnemonic',
      createdAt: 0,
    );

APISpendPath _path({
  required int threshold,
  required List<String> mfps,
  int relTimelockBlocks = 0,
  int absTimelockValue = 0,
}) =>
    APISpendPath(
      id: 0,
      policyPath: const [],
      threshold: threshold,
      mfps: mfps,
      relTimelock: APIRelativeTimelock(
        timelockType: APIRelativeTimelockType.blocks,
        value: relTimelockBlocks,
      ),
      absTimelock: APIAbsoluteTimelock(
        timelockType: APIAbsoluteTimelockType.blocks,
        value: absTimelockValue,
      ),
      wuBase: 0,
      wuIn: 0,
      wuOut: 0,
      trDepth: 0,
      keyChanges: const {},
      vbSweep: 0,
    );

const _minBlocks = 52560; // ~1 year, arbitrary threshold for tests

void main() {
  group('computeWalletTemperature', () {
    test('2-of-3 with only 1 hot key on the main path is cold', () {
      final path = _path(threshold: 2, mfps: ['aaaaaaaa', 'bbbbbbbb', 'cccccccc']);
      final result = computeWalletTemperature(
        spendPaths: [path],
        hotKeys: [_hotKey('aaaaaaaa')],
        minTimelockBlocks: _minBlocks,
      );
      expect(result, WalletTemperature.cold);
    });

    test('2-of-3 with 2 hot keys on the main (non-inheritance) path is hot', () {
      final path = _path(threshold: 2, mfps: ['aaaaaaaa', 'bbbbbbbb', 'cccccccc']);
      final result = computeWalletTemperature(
        spendPaths: [path],
        hotKeys: [_hotKey('aaaaaaaa'), _hotKey('bbbbbbbb')],
        minTimelockBlocks: _minBlocks,
      );
      expect(result, WalletTemperature.hot);
    });

    test('satisfied inheritance path (relative timelock) with unsatisfied main path is warm', () {
      final main = _path(threshold: 2, mfps: ['aaaaaaaa', 'bbbbbbbb']);
      final inheritance = _path(
        threshold: 1,
        mfps: ['cccccccc'],
        relTimelockBlocks: _minBlocks,
      );
      final result = computeWalletTemperature(
        spendPaths: [main, inheritance],
        hotKeys: [_hotKey('cccccccc')],
        minTimelockBlocks: _minBlocks,
      );
      expect(result, WalletTemperature.warm);
    });

    test('satisfied inheritance path (absolute timelock) with unsatisfied main path is warm', () {
      final main = _path(threshold: 2, mfps: ['aaaaaaaa', 'bbbbbbbb']);
      final inheritance = _path(
        threshold: 1,
        mfps: ['cccccccc'],
        absTimelockValue: 800000,
      );
      final result = computeWalletTemperature(
        spendPaths: [main, inheritance],
        hotKeys: [_hotKey('cccccccc')],
        minTimelockBlocks: _minBlocks,
      );
      expect(result, WalletTemperature.warm);
    });

    test('no hot keys is cold', () {
      final path = _path(threshold: 1, mfps: ['aaaaaaaa']);
      final result = computeWalletTemperature(
        spendPaths: [path],
        hotKeys: const [],
        minTimelockBlocks: _minBlocks,
      );
      expect(result, WalletTemperature.cold);
    });

    test('no spend paths is cold', () {
      final result = computeWalletTemperature(
        spendPaths: const [],
        hotKeys: [_hotKey('aaaaaaaa')],
        minTimelockBlocks: _minBlocks,
      );
      expect(result, WalletTemperature.cold);
    });

    test('main and inheritance paths both satisfied is hot', () {
      final main = _path(threshold: 1, mfps: ['aaaaaaaa']);
      final inheritance = _path(
        threshold: 1,
        mfps: ['bbbbbbbb'],
        relTimelockBlocks: _minBlocks,
      );
      final result = computeWalletTemperature(
        spendPaths: [main, inheritance],
        hotKeys: [_hotKey('aaaaaaaa'), _hotKey('bbbbbbbb')],
        minTimelockBlocks: _minBlocks,
      );
      expect(result, WalletTemperature.hot);
    });
  });

  group('isInheritancePath', () {
    test('relative timelock below threshold is not inheritance', () {
      final path = _path(threshold: 1, mfps: ['aaaaaaaa'], relTimelockBlocks: _minBlocks - 1);
      expect(isInheritancePath(path, minTimelockBlocks: _minBlocks), isFalse);
    });

    test('relative timelock at threshold is inheritance', () {
      final path = _path(threshold: 1, mfps: ['aaaaaaaa'], relTimelockBlocks: _minBlocks);
      expect(isInheritancePath(path, minTimelockBlocks: _minBlocks), isTrue);
    });

    test('relative timelock above threshold is inheritance', () {
      final path = _path(threshold: 1, mfps: ['aaaaaaaa'], relTimelockBlocks: _minBlocks + 1);
      expect(isInheritancePath(path, minTimelockBlocks: _minBlocks), isTrue);
    });

    test('absolute timelock of 0 is not inheritance', () {
      final path = _path(threshold: 1, mfps: ['aaaaaaaa'], absTimelockValue: 0);
      expect(isInheritancePath(path, minTimelockBlocks: _minBlocks), isFalse);
    });

    test('absolute timelock above 0 is inheritance', () {
      final path = _path(threshold: 1, mfps: ['aaaaaaaa'], absTimelockValue: 800000);
      expect(isInheritancePath(path, minTimelockBlocks: _minBlocks), isTrue);
    });
  });
}
