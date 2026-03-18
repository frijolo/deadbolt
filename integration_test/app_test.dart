import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:deadbolt/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app smoke test', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 1. App launches and shows at least one AppBar.
    expect(find.byType(AppBar), findsAtLeast(1));

    // 2. Navigation destinations: Wallet first, Designer second.
    final railElements = find.byType(NavigationRail).evaluate().toList();

    if (railElements.isNotEmpty) {
      // Wide layout (desktop): verify NavigationRail destinations.
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.destinations.length, greaterThanOrEqualTo(2));
      expect(
        (rail.destinations[0].icon as Icon).icon,
        equals(Icons.account_balance_wallet_outlined),
        reason: 'First rail destination must be Wallet',
      );
      expect(
        (rail.destinations[1].icon as Icon).icon,
        equals(Icons.design_services_outlined),
        reason: 'Second rail destination must be Designer',
      );
    } else {
      // Narrow layout (mobile): open the drawer and verify destinations.
      final scaffolds = find.byType(Scaffold).evaluate().toList();
      expect(scaffolds, isNotEmpty,
          reason: 'Expected at least one Scaffold in narrow layout');

      ((scaffolds.first as StatefulElement).state as ScaffoldState)
          .openDrawer();
      await tester.pumpAndSettle();

      final destinations = tester
          .widgetList<NavigationDrawerDestination>(
              find.byType(NavigationDrawerDestination))
          .toList();

      expect(destinations.length, greaterThanOrEqualTo(2));
      expect(
        (destinations[0].icon as Icon).icon,
        equals(Icons.account_balance_wallet_outlined),
        reason: 'First destination must be Wallet',
      );
      expect(
        (destinations[1].icon as Icon).icon,
        equals(Icons.design_services_outlined),
        reason: 'Second destination must be Designer',
      );
    }
  });
}
