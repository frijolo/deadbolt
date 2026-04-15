import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/biometric_lock_cubit.dart';
import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/cubit/settings_cubit.dart';
import 'package:deadbolt/cubit/wallet_list_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/services/biometric_service.dart';
import 'package:deadbolt/services/nostr_relay_settings.dart';
import 'package:deadbolt/services/wallet_service.dart';
import 'package:deadbolt/services/wallet_sync_service.dart';
import 'package:deadbolt/src/rust/frb_generated.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/root_navigator.dart';
import 'package:deadbolt/widgets/app_scaffold.dart';
import 'package:deadbolt/widgets/biometric_lock_screen.dart';

Future<void> main() async {
  // Global error handler for async errors not caught by Flutter
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await RustLib.init();
      await NostrRelaySettings().applyToRust();

      // Global error handler for Flutter framework errors
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        debugPrint('════════════════════════════════════════════════════════════');
        debugPrint('FLUTTER ERROR:');
        debugPrint('${details.exception}');
        debugPrint('Stack trace:');
        debugPrint('${details.stack}');
        debugPrint('════════════════════════════════════════════════════════════');
      };

      final db = AppDatabase();
      runApp(DeadboltApp(db: db));
    },
    (error, stackTrace) {
      debugPrint('════════════════════════════════════════════════════════════');
      debugPrint('UNCAUGHT ASYNC ERROR:');
      debugPrint('$error');
      debugPrint('Stack trace:');
      debugPrint('$stackTrace');
      debugPrint('════════════════════════════════════════════════════════════');
    },
  );
}

class DeadboltApp extends StatelessWidget {
  final AppDatabase db;

  const DeadboltApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: db),
        RepositoryProvider<WalletService>(create: (_) => WalletService()),
        RepositoryProvider<WalletSyncService>(
          create: (c) => WalletSyncService(c.read<WalletService>()),
        ),
        RepositoryProvider<BiometricService>(create: (_) => BiometricService()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => SettingsCubit()),
          BlocProvider(
            create: (c) => BiometricLockCubit(c.read<SettingsCubit>()),
          ),
          BlocProvider(create: (_) => ProjectListCubit(db)),
          BlocProvider(create: (c) => WalletListCubit(
            service: c.read<WalletService>(),
            syncService: c.read<WalletSyncService>(),
          )),
        ],
        child: BlocBuilder<SettingsCubit, AppSettings>(
          builder: (context, settings) => MaterialApp(
            navigatorKey: rootNavigatorKey,
            title: 'Deadbolt',
            debugShowCheckedModeBanner: false,
            locale: settings.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppThemeManager.getLightThemeData(),
            darkTheme: AppThemeManager.getDarkThemeData(),
            themeMode: AppThemeManager.getThemeMode(settings.appTheme),
            home: BlocBuilder<BiometricLockCubit, bool>(
              builder: (context, isLocked) =>
                  isLocked ? const BiometricLockScreen() : const AppScaffold(),
            ),
          ),
        ),
      ),
    );
  }
}
