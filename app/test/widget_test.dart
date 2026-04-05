import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:unearth_radio/src/app.dart';
import 'package:unearth_radio/src/core/router/app_router.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // Create a minimal GoRouter that doesn't depend on Supabase.
    final testRouter = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Test'))),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Override the router so we skip Supabase auth redirects.
          appRouterProvider.overrideWithValue(testRouter),
        ],
        child: const UnearthRadioApp(),
      ),
    );

    // The app should render a MaterialApp.router at its root.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
