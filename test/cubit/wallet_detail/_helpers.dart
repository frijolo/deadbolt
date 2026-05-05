import 'package:biometric_storage/biometric_storage.dart' show PromptInfo;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deadbolt/cubit/loaded_wallet.dart' show LoadedWallet;
import 'package:deadbolt/cubit/wallet_detail_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_session.dart';
import 'package:deadbolt/cubit/wallet_op_result.dart';
import 'package:deadbolt/cubit/wallet_opener.dart';
import 'package:deadbolt/cubit/wallet_deltas.dart';
import 'package:deadbolt/services/price_service.dart' show PriceProviderType;
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/src/rust/api/wallet.dart' show ApiWallet;

class MockWalletOpener extends Mock implements WalletOpener {}

class MockWalletSyncService extends Mock implements WalletSyncService {}

class MockLoadedWallet extends Mock implements LoadedWallet {}

class MockApiWallet extends Mock implements ApiWallet {}

class FakePromptInfo extends Fake implements PromptInfo {}

const String walletPath = '/wallets/w.db';

APIBalance balanceOf(int sats) => APIBalance(
      confirmed: BigInt.from(sats),
      trustedPending: BigInt.zero,
      untrustedPending: BigInt.zero,
      immature: BigInt.zero,
    );

APIWalletInfo walletInfoFixture({String descriptor = 'tr(...)'}) =>
    APIWalletInfo(
      walletPath: walletPath,
      name: 'w',
      descriptor: descriptor,
      network: APINetwork.signet,
      createdAt: 0,
      protection: const APIWalletProtection(
        protectionType: APIProtectionType.deviceKey,
        needsPassword: false,
        securityLevel: APISecurityLevel.standard,
      ),
    );

APITransactionPage emptyPage() =>
    const APITransactionPage(transactions: [], totalCount: 0, hasMore: false);

APIAddress addressFixture(String a, {int idx = 0, APIKeychain kc = APIKeychain.external_}) =>
    APIAddress(
      address: a,
      index: idx,
      keychain: kc,
      balanceSat: BigInt.zero,
      isUsed: false,
      txCount: 0,
      isAuto: false,
    );

APIPsbtInfo psbtFixture({int id = 1, String b64 = 'cHNidA==', String txid = 'tx'}) =>
    APIPsbtInfo(
      id: id,
      psbtBase64: b64,
      txid: txid,
      isAuto: false,
      isSelfTransfer: false,
      createdAt: 0,
      recipient: 'addr',
      amountSat: BigInt.from(1000),
      recipients: const [],
      feeSat: BigInt.from(100),
      spendPathId: 0,
      threshold: 1,
      mfps: const [],
      hasSpentInputs: false,
    );

APIPsbtAnalysis analysisFixture({bool finalized = false}) =>
    APIPsbtAnalysis(signers: const [], isFinalized: finalized);

APIHotKeyInfo hotKeyFixture(String mfp) =>
    APIHotKeyInfo(mfp: mfp, seedType: 'mnemonic', createdAt: 0);

WalletDetailView viewFixture({
  bool receiveLoaded = true,
  bool changeLoaded = true,
  bool utxosLoaded = true,
  bool psbtsLoaded = true,
  String descriptor = 'tr(...)',
  List<APIPsbtInfo> psbts = const [],
  List<APIHotKeyInfo> hotKeys = const [],
  TransactionPage? transactions,
  bool hasBiometricSlot = false,
}) =>
    WalletDetailView(
      info: WalletInfo(
        walletInfo: walletInfoFixture(descriptor: descriptor),
        balance: balanceOf(0),
        hasBiometricSlot: hasBiometricSlot,
        tipHeight: 100,
      ),
      transactions: transactions ??
          const TransactionPage(
            transactions: [],
            totalCount: 0,
            hasMore: false,
            currentPage: 0,
          ),
      addresses: AddressView(
        receiveAddresses: const [],
        changeAddresses: const [],
        receiveLoaded: receiveLoaded,
        changeLoaded: changeLoaded,
        selectedKeychain: 0,
      ),
      coins: CoinView(utxos: const [], loaded: utxosLoaded),
      descriptor: const DescriptorView(keyLabels: {}, pathLabels: {}, loaded: false),
      psbts: PsbtList(psbts: psbts, analyses: const {}, loaded: psbtsLoaded),
      hotKeys: hotKeys,
      fiat: const FiatPrices(prices: {}),
    );

/// Default-stub a [MockLoadedWallet] with safe `Ok(...)` answers for every
/// method used opportunistically by `lifecycle.load()` and
/// `selectTab` (via `loadDescriptorAnalysis`). Returns the [MockApiWallet]
/// exposed via `wallet.handle` so callers can stub direct FFI calls.
MockApiWallet stubLoadedDefaults(MockLoadedWallet w, {MockApiWallet? handle}) {
  final h = handle ?? MockApiWallet();
  when(() => w.handle).thenReturn(h);
  when(() => w.loadDescriptorAnalysis(any())).thenAnswer(
    (_) async => const Ok(DescriptorSnapshot(
      analysis: APIAnalysisResult(
        descriptor: 'tr(...)',
        network: APINetwork.signet,
        walletType: APIWalletType.p2Tr,
        keys: [],
        spendPaths: [],
      ),
      keyLabels: {},
      pathLabels: {},
    )),
  );
  // Note: don't pre-stub fetchFiatPrices here — leftover any() matchers from
  // setUp can bleed into the next test's matcher state. Tests that exercise
  // fiat must stub it explicitly.
  return h;
}

/// Build a cubit and drive it to `WalletDetailLoaded` via the opener stub.
Future<WalletDetailCubit> loadCubit({
  required MockWalletOpener opener,
  required MockWalletSyncService sync,
  required MockLoadedWallet wallet,
  WalletDetailView? view,
}) async {
  when(() => opener.load(
        walletPath: any(named: 'walletPath'),
        password: any(named: 'password'),
        biometricUnlockReason: any(named: 'biometricUnlockReason'),
      )).thenAnswer((_) async => WalletLoadSuccess(view ?? viewFixture(), wallet));

  final cubit = WalletDetailCubit(opener: opener, syncService: sync);
  await cubit.load(walletPath);
  // Let any unawaited descriptor analysis settle so subsequent emits don't race.
  await Future.delayed(Duration.zero);
  return cubit;
}

class _FakeApiWallet extends Fake implements ApiWallet {}

class _FakeSyncEvent extends Fake implements WalletSyncEvent {}

void registerCommonFallbacks() {
  registerFallbackValue(APIKeychain.external_);
  registerFallbackValue(FakePromptInfo());
  registerFallbackValue(_FakeApiWallet());
  registerFallbackValue(_FakeSyncEvent());
  registerFallbackValue(<APIPsbtInfo>[]);
  registerFallbackValue(<int, APIPsbtAnalysis>{});
  registerFallbackValue(APIProtectionType.deviceKey);
  registerFallbackValue(APISecurityLevel.standard);
  registerFallbackValue(<APIPubKey>[]);
  registerFallbackValue(<String>{});
  registerFallbackValue(PriceProviderType.coinGecko);
}
