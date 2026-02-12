import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:deadbolt/cubit/project_list_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/screens/project_list_screen.dart';
import 'package:deadbolt/src/rust/frb_generated.dart';

Future<void> main() async {
  // Global error handler for async errors not caught by Flutter
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await RustLib.init();

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
      ],
      child: BlocProvider(
        create: (_) => ProjectListCubit(db),
        child: MaterialApp(
          title: 'Deadbolt',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.orange,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: const ProjectListScreen(),
        ),
      ),
    );
  }
}
