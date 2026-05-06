import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surreal_rap/main.dart';

void main() {
  testWidgets('adds a new rap idea', (tester) async {
    await tester.pumpWidget(const SurrealRapApp());

    expect(find.text('SurrealRap'), findsOneWidget);
    expect(find.text('New hook idea'), findsNothing);

    await tester.enterText(find.byType(EditableText), 'New hook idea');
    await tester.tap(find.text('Add Idea'));
    await tester.pump();

    expect(find.text('New hook idea'), findsOneWidget);
  });
}
