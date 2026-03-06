import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_detail_cubit.dart'
    show WalletDetailCubit, APICoinControl;
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/errors.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/screens/psbt_detail_screen.dart';

/// Screen for building an unsigned PSBT with optional coin control.
///
/// [preSelectedUtxos] are the coins already checked in the Coins tab.
/// [spendPaths] come from the wallet's descriptor analysis (may be null if
/// the descriptor tab hasn't been loaded yet — in that case we show a message).
class CreateTxScreen extends StatefulWidget {
  final List<APIUtxo> preSelectedUtxos;
  final List<APISpendPath>? spendPaths;
  final Map<String, String> keyLabels;
  final Map<int, String> pathLabels;

  const CreateTxScreen({
    super.key,
    required this.preSelectedUtxos,
    this.spendPaths,
    this.keyLabels = const {},
    this.pathLabels = const {},
  });

  static Future<void> push(
    BuildContext context, {
    required List<APIUtxo> preSelectedUtxos,
    List<APISpendPath>? spendPaths,
    Map<String, String> keyLabels = const {},
    Map<int, String> pathLabels = const {},
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<WalletDetailCubit>(),
          child: CreateTxScreen(
            preSelectedUtxos: preSelectedUtxos,
            spendPaths: spendPaths,
            keyLabels: keyLabels,
            pathLabels: pathLabels,
          ),
        ),
      ),
    );
  }

  @override
  State<CreateTxScreen> createState() => _CreateTxScreenState();
}

class _CreateTxScreenState extends State<CreateTxScreen> {
  final _formKey = GlobalKey<FormState>();
  final _recipientCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _feeRateCtrl = TextEditingController(text: '1.0');
  bool _creating = false;
  bool _sendMax = false;
  APISpendPath? _selectedPath;

  @override
  void initState() {
    super.initState();
    // Pre-select first spend path if available
    if (widget.spendPaths != null && widget.spendPaths!.isNotEmpty) {
      _selectedPath = widget.spendPaths!.first;
    }
  }

  @override
  void dispose() {
    _recipientCtrl.dispose();
    _amountCtrl.dispose();
    _feeRateCtrl.dispose();
    super.dispose();
  }

  int get _selectedSats =>
      widget.preSelectedUtxos.fold(0, (sum, u) => sum + u.valueSat.toInt());

  void _toggleSendMax() {
    setState(() {
      _sendMax = !_sendMax;
      if (_sendMax) {
        _amountCtrl.clear();
      }
    });
  }

  void _fillSelfPaymentAddress() {
    final l10n = context.l10n;
    final address = context.read<WalletDetailCubit>().getNextSelfPaymentAddress();
    if (address == null) {
      showErrorToast(context, l10n.createTxNoUnusedAddress);
      return;
    }
    setState(() => _recipientCtrl.text = address);
  }

  String _pathLabel(APISpendPath path) {
    final label = widget.pathLabels[path.id];
    if (label != null && label.isNotEmpty) return label;
    final keys = path.mfps
        .map((m) => widget.keyLabels[m] ?? m.substring(0, 4).toUpperCase())
        .join(' + ');
    final threshold = '${path.threshold}-of-${path.mfps.length}';
    return '$threshold ($keys)';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPath == null) return;

    final l10n = context.l10n;
    final feeRate = double.tryParse(_feeRateCtrl.text.trim()) ?? 0;
    final amount = _sendMax ? 0 : (int.tryParse(_amountCtrl.text.trim()) ?? 0);

    setState(() => _creating = true);
    try {
      final cubit = context.read<WalletDetailCubit>();
      final selectedUtxos = widget.preSelectedUtxos
          .map((u) => APICoinControl(txid: u.txid, vout: u.vout))
          .toList();

      final psbt = await cubit.createPsbt(
        recipientAddress: _recipientCtrl.text.trim(),
        amountSat: amount,
        feeRateSatPerVb: feeRate,
        selectedUtxos: selectedUtxos,
        policyPath: _selectedPath!.policyPath,
        spendPathId: _selectedPath!.id,
        threshold: _selectedPath!.threshold,
        mfps: _selectedPath!.mfps,
        sendMax: _sendMax,
      );

      if (!mounted) return;
      if (psbt != null) {
        showSuccessToast(context, l10n.createTxSuccess);
        // Replace this screen with PSBT detail
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BlocProvider.value(
              value: cubit,
              child: PsbtDetailScreen(psbt: psbt, spendPath: _selectedPath!),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) showErrorToast(context, formatRustError(e));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final hasSelection = widget.preSelectedUtxos.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.createTxTitle)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Selected coins summary
              if (hasSelection)
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.toll, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.createTxSelectedCoins(
                              widget.preSelectedUtxos.length,
                              _selectedSats,
                            ),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    l10n.createTxAutoSelect,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurface.withAlpha(150)),
                  ),
                ),

              // Recipient
              TextFormField(
                controller: _recipientCtrl,
                decoration: InputDecoration(
                  labelText: l10n.createTxRecipient,
                  hintText: l10n.createTxRecipientHint,
                  suffixIcon: TextButton(
                    onPressed: _fillSelfPaymentAddress,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurface.withAlpha(150),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Text(l10n.createTxSelfPayButton),
                  ),
                ),
                keyboardType: TextInputType.text,
                autocorrect: false,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.createTxRecipientRequired : null,
              ),
              const SizedBox(height: 16),

              // Amount
              TextFormField(
                controller: _amountCtrl,
                enabled: !_sendMax,
                decoration: InputDecoration(
                  labelText: l10n.createTxAmount,
                  hintText: _sendMax ? l10n.createTxSendMax : null,
                  suffixIcon: TextButton(
                    onPressed: _toggleSendMax,
                    style: TextButton.styleFrom(
                      foregroundColor: _sendMax
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withAlpha(150),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Text(l10n.createTxMaxButton),
                  ),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (_sendMax) return null;
                  if (v == null || v.trim().isEmpty) return l10n.createTxAmountRequired;
                  final n = int.tryParse(v.trim());
                  if (n == null || n <= 0) return l10n.createTxAmountInvalid;
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Fee rate
              TextFormField(
                controller: _feeRateCtrl,
                decoration: InputDecoration(
                  labelText: l10n.createTxFeeRate,
                  hintText: l10n.createTxFeeRateHint,
                  suffixText: 'sat/vB',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final minFeeRate =
                      context.read<SettingsCubit>().state.minFeeRate;
                  final n = double.tryParse(v?.trim() ?? '');
                  if (n == null || n < minFeeRate) {
                    return l10n.createTxFeeRateMin(minFeeRate.toString());
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Spend path selector
              if (widget.spendPaths == null || widget.spendPaths!.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    l10n.createTxNoSpendPaths,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                )
              else
                DropdownButtonFormField<APISpendPath>(
                  initialValue: _selectedPath,
                  decoration: InputDecoration(labelText: l10n.createTxSpendPath),
                  items: widget.spendPaths!
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(_pathLabel(p), overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (p) => setState(() => _selectedPath = p),
                  validator: (v) => v == null ? l10n.createTxSpendPathHint : null,
                ),

              const SizedBox(height: 32),

              FilledButton(
                onPressed:
                    (_creating || _selectedPath == null) ? null : _submit,
                child: _creating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.createTxButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
