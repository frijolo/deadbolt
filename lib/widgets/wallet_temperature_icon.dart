import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/toast_helper.dart';
import 'package:deadbolt/utils/wallet_temperature.dart';

/// Small informational icon showing whether the wallet holds enough private
/// key material in the app to sign for its main spend path (hot), only for
/// an inheritance/recovery path (warm), or none at all (cold).
class WalletTemperatureIcon extends StatelessWidget {
  final WalletTemperature temperature;

  const WalletTemperatureIcon({super.key, required this.temperature});

  (IconData, Color) _iconAndColor() {
    switch (temperature) {
      case WalletTemperature.hot:
        return (Icons.local_fire_department, Colors.red);
      case WalletTemperature.warm:
        return (Icons.local_fire_department_outlined, Colors.orange);
      case WalletTemperature.cold:
        return (Icons.visibility_outlined, Colors.blue);
    }
  }

  String _message(AppLocalizations l10n) {
    switch (temperature) {
      case WalletTemperature.hot:
        return l10n.walletTemperatureHotToast;
      case WalletTemperature.warm:
        return l10n.walletTemperatureWarmToast;
      case WalletTemperature.cold:
        return l10n.walletTemperatureColdToast;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (icon, color) = _iconAndColor();
    final message = _message(l10n);
    return IconButton(
      icon: Icon(icon, color: color.withAlpha(AppAlpha.high), size: 18),
      tooltip: message,
      onPressed: () => showInfoToast(message),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
    );
  }
}
