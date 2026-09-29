// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:jaguza/app.dart';

void main() {
  testWidgets('home opens the photos tab', (WidgetTester tester) async {
    await tester.pumpWidget(const CaptureApp());

    expect(find.text('Open camera'), findsOneWidget);
    expect(find.text('Recent photo'), findsOneWidget);

    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();

    expect(find.text('No photos yet'), findsOneWidget);
  });
}
