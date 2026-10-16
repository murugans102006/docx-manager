import 'package:college_document_client/screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the sign-in form and registration entry point', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);

    await tester.tap(find.text('Create a student account'));
    await tester.pumpAndSettle();
    expect(find.text('Create student account'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('renders actual request progress and activity history', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RequestTimeline(
            status: 'pending_verification',
            history: [
              {'status': 'submitted', 'createdAt': '2026-01-01'},
              {'status': 'document_generated', 'createdAt': '2026-01-02'},
            ],
          ),
        ),
      ),
    );

    expect(find.text('Progress'), findsNothing);
    expect(find.text('Signing'), findsOneWidget);
    expect(find.text('Verification'), findsOneWidget);
    expect(find.text('Activity history'), findsOneWidget);
    expect(find.text('Document Generated'), findsOneWidget);
  });
}
