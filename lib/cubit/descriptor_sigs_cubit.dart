import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/cubit_error_logger.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/src/rust/api/model.dart'
    show APIDescriptorSig, APINetwork, APIPubKey;
import 'package:deadbolt/src/rust/api/wallet.dart' show ApiWallet;
import 'package:deadbolt/src/rust/api/wallet/descriptor_sig.dart'
    show APIPrepareDescriptorSigPsbt;

export 'package:deadbolt/src/rust/api/model.dart'
    show APIDescriptorSig, APINetwork, APIPubKey;
export 'package:deadbolt/src/rust/api/wallet/descriptor_sig.dart'
    show APIPrepareDescriptorSigPsbt;

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

sealed class DescriptorSigsState {}

class DescriptorSigsLoading extends DescriptorSigsState {}

class DescriptorSigsLoaded extends DescriptorSigsState {
  /// Participating keys extracted from the descriptor (one per cosigner).
  final List<APIPubKey> participatingKeys;

  /// Currently stored signatures (may be fewer than participatingKeys).
  final List<APIDescriptorSig> sigs;

  /// MFPs that have a hot key loaded in this wallet.
  final Set<String> hotKeyMfps;

  /// Network of the wallet (needed for BB02 signing).
  final APINetwork network;

  /// True once [DescriptorSigsCubit.verify] has completed successfully at
  /// least once, so the UI can show verified/invalid labels instead of just
  /// "signed".
  final bool hasVerified;

  DescriptorSigsLoaded({
    required this.participatingKeys,
    required this.sigs,
    required this.hotKeyMfps,
    required this.network,
    this.hasVerified = false,
  });

  DescriptorSigsLoaded copyWith({
    List<APIPubKey>? participatingKeys,
    List<APIDescriptorSig>? sigs,
    Set<String>? hotKeyMfps,
    APINetwork? network,
    bool? hasVerified,
  }) =>
      DescriptorSigsLoaded(
        participatingKeys: participatingKeys ?? this.participatingKeys,
        sigs: sigs ?? this.sigs,
        hotKeyMfps: hotKeyMfps ?? this.hotKeyMfps,
        network: network ?? this.network,
        hasVerified: hasVerified ?? this.hasVerified,
      );

  APIDescriptorSig? sigForMfp(String mfp) =>
      sigs.firstWhereOrNull((s) => s.mfp == mfp);

  int get signedCount => sigs.length;
  int get totalCount => participatingKeys.length;
}

class DescriptorSigsError extends DescriptorSigsState {
  final String message;
  DescriptorSigsError(this.message);
}

// ---------------------------------------------------------------------------
// Cubit
// ---------------------------------------------------------------------------

class DescriptorSigsCubit extends Cubit<DescriptorSigsState>
    with CubitErrorLogger {
  final ApiWallet _wallet;

  /// Participating keys extracted from the descriptor, injected by the caller
  /// (available from WalletDetailLoaded.descriptorAnalysis.keys).
  final List<APIPubKey> _participatingKeys;

  /// MFPs that have a hot key loaded in this wallet.
  final Set<String> _hotKeyMfps;

  /// Bitcoin network of the wallet (used for BB02 PSBT signing).
  final APINetwork _network;

  DescriptorSigsCubit({
    required ApiWallet wallet,
    required List<APIPubKey> participatingKeys,
    Set<String> hotKeyMfps = const {},
    APINetwork network = APINetwork.bitcoin,
  })  : _wallet = wallet,
        _participatingKeys = participatingKeys,
        _hotKeyMfps = hotKeyMfps,
        _network = network,
        super(DescriptorSigsLoading());

  // ── Load ────────────────────────────────────────────────────────────────

  Future<void> load() async {
    emit(DescriptorSigsLoading());
    try {
      final sigs = _wallet.listDescriptorSigs();
      emit(DescriptorSigsLoaded(
        participatingKeys: _participatingKeys,
        sigs: sigs,
        hotKeyMfps: _hotKeyMfps,
        network: _network,
      ));
    } catch (e, st) {
      logError('DescriptorSigsCubit.load()', e, st);
      emit(DescriptorSigsError(formatRustError(e)));
    }
  }

  // ── Sign with HotKey ────────────────────────────────────────────────────

  Future<void> signWithHotKey(String mfp) async {
    final current = _currentLoaded;
    if (current == null) return;
    try {
      final sig = _wallet.signDescriptorWithHotkey(mfp: mfp);
      final updated = _upsertSig(current.sigs, sig);
      emit(current.copyWith(sigs: updated));
    } catch (e, st) {
      logError('DescriptorSigsCubit.signWithHotKey()', e, st);
      rethrow;
    }
  }

  // ── Prepare PSBT (BB02 or QR Variant B) ────────────────────────────────

  /// Returns the prepared PSBT data.  The UI then drives the signing flow
  /// and calls [completeSigFromPsbt] once done.
  APIPrepareDescriptorSigPsbt preparePsbt(String mfp) {
    return _wallet.prepareDescriptorSigPsbt(mfp: mfp);
  }

  Future<void> completeSigFromPsbt({
    required String mfp,
    required String xpubEntry,
    required String signedPsbtB64,
  }) async {
    final current = _currentLoaded;
    if (current == null) return;
    try {
      final sig = _wallet.completeDescriptorSigFromPsbt(
        mfp: mfp,
        xpubEntry: xpubEntry,
        signedPsbtB64: signedPsbtB64,
      );
      final updated = _upsertSig(current.sigs, sig);
      emit(current.copyWith(sigs: updated));
    } catch (e, st) {
      logError('DescriptorSigsCubit.completeSigFromPsbt()', e, st);
      rethrow;
    }
  }

  // ── QR Message Signature (Variant A) ───────────────────────────────────

  Future<void> addSigFromMessage({
    required String mfp,
    required String xpubEntry,
    required String sigB64,
  }) async {
    final current = _currentLoaded;
    if (current == null) return;
    try {
      final sig = _wallet.addDescriptorSigFromMessage(
        mfp: mfp,
        xpubEntry: xpubEntry,
        sigB64: sigB64,
      );
      final updated = _upsertSig(current.sigs, sig);
      emit(current.copyWith(sigs: updated));
    } catch (e, st) {
      logError('DescriptorSigsCubit.addSigFromMessage()', e, st);
      rethrow;
    }
  }

  // ── Delete ──────────────────────────────────────────────────────────────

  Future<void> deleteSig(String mfp) async {
    final current = _currentLoaded;
    if (current == null) return;
    try {
      _wallet.deleteDescriptorSig(mfp: mfp);
      final updated = current.sigs.where((s) => s.mfp != mfp).toList();
      emit(current.copyWith(sigs: updated));
    } catch (e, st) {
      logError('DescriptorSigsCubit.deleteSig()', e, st);
      rethrow;
    }
  }

  // ── Verify ─────────────────────────────────────────────────────────────

  Future<void> verify() async {
    final current = _currentLoaded;
    if (current == null) return;
    try {
      final sigs = _wallet.verifyDescriptorSigs();
      emit(current.copyWith(sigs: sigs, hasVerified: true));
    } catch (e, st) {
      logError('DescriptorSigsCubit.verify()', e, st);
      rethrow;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  DescriptorSigsLoaded? get _currentLoaded {
    final s = state;
    return s is DescriptorSigsLoaded ? s : null;
  }

  static List<APIDescriptorSig> _upsertSig(
      List<APIDescriptorSig> existing, APIDescriptorSig sig) {
    final updated = existing.where((s) => s.mfp != sig.mfp).toList();
    updated.add(sig);
    return updated;
  }
}
