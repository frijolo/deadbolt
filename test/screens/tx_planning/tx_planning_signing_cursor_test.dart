import 'dart:typed_data';

import 'package:deadbolt/screens/tx_planning/tx_planning_signing_cursor.dart';
import 'package:deadbolt/src/rust/api/model.dart'
    show
        APINetwork,
        APIPsbtSignerStatus,
        APISpacedPlanChildPsbt,
        APISpacedPlanSigningBundle;
import 'package:flutter_test/flutter_test.dart';

const _mfpA = 'aaaaaaaa';
const _mfpB = 'bbbbbbbb';
const _mfpC = 'cccccccc';

APISpacedPlanChildPsbt _child({
  required int id,
  required bool finalized,
  required Map<String, bool> signers,
}) =>
    APISpacedPlanChildPsbt(
      psbtId: id,
      psbtB64: 'b64-$id',
      signers: [
        for (final e in signers.entries)
          APIPsbtSignerStatus(mfp: e.key, hasSigned: e.value),
      ],
      isFinalized: finalized,
    );

APISpacedPlanSigningBundle _bundle(List<APISpacedPlanChildPsbt> children) =>
    APISpacedPlanSigningBundle(
      planId: 1,
      descriptor: 'wsh(multi(2,A,B,C))',
      network: APINetwork.bitcoin,
      threshold: 2,
      mfps: const [_mfpA, _mfpB, _mfpC],
      keyChanges: {
        _mfpA: Uint32List.fromList([0, 1]),
        _mfpB: Uint32List.fromList([0, 1]),
        _mfpC: Uint32List.fromList([0, 1]),
      },
      children: children,
    );

void main() {
  group('firstUnfinalizedFrom', () {
    test('returns from when current child is unfinalized', () {
      final b = _bundle([
        _child(id: 1, finalized: false, signers: {_mfpA: false, _mfpB: false}),
        _child(id: 2, finalized: false, signers: {_mfpA: false, _mfpB: false}),
      ]);
      expect(b.firstUnfinalizedFrom(0), 0);
      expect(b.firstUnfinalizedFrom(1), 1);
    });

    test('skips finalized children', () {
      final b = _bundle([
        _child(id: 1, finalized: true, signers: {_mfpA: true, _mfpB: true}),
        _child(id: 2, finalized: true, signers: {_mfpA: true, _mfpB: true}),
        _child(id: 3, finalized: false, signers: {_mfpA: true, _mfpB: false}),
      ]);
      expect(b.firstUnfinalizedFrom(0), 2);
    });

    test('returns length when every child is finalized', () {
      final b = _bundle([
        _child(id: 1, finalized: true, signers: {_mfpA: true, _mfpB: true}),
        _child(id: 2, finalized: true, signers: {_mfpA: true, _mfpB: true}),
      ]);
      expect(b.firstUnfinalizedFrom(0), 2);
    });
  });

  group('firstPendingForMfp — singlesig (one signer)', () {
    test('walks unsigned children for the active key', () {
      final b = _bundle([
        _child(id: 1, finalized: false, signers: {_mfpA: false}),
        _child(id: 2, finalized: false, signers: {_mfpA: false}),
      ]);
      expect(b.firstPendingForMfp(0, _mfpA), 0);
    });

    test('skips children already signed by the active key', () {
      final b = _bundle([
        _child(id: 1, finalized: false, signers: {_mfpA: true}),
        _child(id: 2, finalized: false, signers: {_mfpA: true}),
        _child(id: 3, finalized: false, signers: {_mfpA: false}),
      ]);
      expect(b.firstPendingForMfp(0, _mfpA), 2);
    });

    test('returns length when nothing is pending', () {
      final b = _bundle([
        _child(id: 1, finalized: true, signers: {_mfpA: true}),
        _child(id: 2, finalized: true, signers: {_mfpA: true}),
      ]);
      expect(b.firstPendingForMfp(0, _mfpA), 2);
    });
  });

  group('firstPendingForMfp — multisig 2-of-3', () {
    test(
        'after round 1 by A on first half, A resumes at the first non-A-signed '
        'child even though none are finalized', () {
      final b = _bundle([
        _child(id: 1, finalized: false, signers: {
          _mfpA: true,
          _mfpB: false,
          _mfpC: false,
        }),
        _child(id: 2, finalized: false, signers: {
          _mfpA: true,
          _mfpB: false,
          _mfpC: false,
        }),
        _child(id: 3, finalized: false, signers: {
          _mfpA: false,
          _mfpB: false,
          _mfpC: false,
        }),
        _child(id: 4, finalized: false, signers: {
          _mfpA: false,
          _mfpB: false,
          _mfpC: false,
        }),
      ]);
      expect(b.firstPendingForMfp(0, _mfpA), 2);
    });

    test(
        'after round 1 fully by A, B starts at index 0 because B has signed '
        'nothing yet', () {
      final b = _bundle([
        _child(id: 1, finalized: false, signers: {
          _mfpA: true,
          _mfpB: false,
          _mfpC: false,
        }),
        _child(id: 2, finalized: false, signers: {
          _mfpA: true,
          _mfpB: false,
          _mfpC: false,
        }),
      ]);
      expect(b.firstPendingForMfp(0, _mfpA), 2); // A is done
      expect(b.firstPendingForMfp(0, _mfpB), 0); // B still on round 1
    });

    test('skips finalized children even when the active key did not sign them',
        () {
      final b = _bundle([
        _child(id: 1, finalized: true, signers: {
          _mfpA: true,
          _mfpB: true,
          _mfpC: false,
        }),
        _child(id: 2, finalized: false, signers: {
          _mfpA: false,
          _mfpB: true,
          _mfpC: false,
        }),
      ]);
      // C never signed child 1 (B + A did) but it's finalized -> skip.
      expect(b.firstPendingForMfp(0, _mfpC), 1);
    });

    test('honours the `from` offset', () {
      final b = _bundle([
        _child(id: 1, finalized: false, signers: {_mfpA: false, _mfpB: false}),
        _child(id: 2, finalized: false, signers: {_mfpA: false, _mfpB: false}),
        _child(id: 3, finalized: false, signers: {_mfpA: false, _mfpB: false}),
      ]);
      expect(b.firstPendingForMfp(2, _mfpA), 2);
    });

    test('skips children whose signer set does not include the active key', () {
      // Unusual but defensive: if a child happens to omit this MFP
      // entirely (e.g. mixed thresholds in a future plan format), we
      // must not return that index — the device can't add a signature.
      final b = _bundle([
        _child(id: 1, finalized: false, signers: {_mfpA: false, _mfpB: false}),
        _child(id: 2, finalized: false, signers: {_mfpA: false, _mfpB: false}),
      ]);
      expect(b.firstPendingForMfp(0, _mfpC), 2);
    });
  });

  group('signedCountForMfp', () {
    test('counts children where the key has signed', () {
      final b = _bundle([
        _child(id: 1, finalized: false, signers: {_mfpA: true, _mfpB: false}),
        _child(id: 2, finalized: false, signers: {_mfpA: true, _mfpB: false}),
        _child(id: 3, finalized: false, signers: {_mfpA: false, _mfpB: true}),
      ]);
      expect(b.signedCountForMfp(_mfpA), 2);
      expect(b.signedCountForMfp(_mfpB), 1);
    });

    test('returns 0 for keys not in any signer set', () {
      final b = _bundle([
        _child(id: 1, finalized: false, signers: {_mfpA: true}),
      ]);
      expect(b.signedCountForMfp(_mfpC), 0);
    });
  });

  group('isKnownMfp', () {
    test('true when at least one child lists the mfp', () {
      final b = _bundle([
        _child(id: 1, finalized: false, signers: {_mfpA: false, _mfpB: false}),
      ]);
      expect(b.isKnownMfp(_mfpA), isTrue);
      expect(b.isKnownMfp(_mfpB), isTrue);
    });

    test('false for a fingerprint absent from every signer set', () {
      final b = _bundle([
        _child(id: 1, finalized: false, signers: {_mfpA: false, _mfpB: false}),
      ]);
      expect(b.isKnownMfp(_mfpC), isFalse);
    });

    test('false on empty bundle', () {
      final b = _bundle(const []);
      expect(b.isKnownMfp(_mfpA), isFalse);
    });
  });
}
