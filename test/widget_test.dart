import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surreal_rap/main.dart';

void main() {
  testWidgets('opens reader and adds an annotation', (tester) async {
    await tester.pumpWidget(const SurrealRapApp());

    expect(find.text('Reading Library'), findsOneWidget);
    expect(find.text('Glass Metro Cantos'), findsOneWidget);

    await tester.tap(find.text('Glass Metro Cantos').first);
    await tester.pumpAndSettle();

    expect(find.text('Reader Tools'), findsOneWidget);
    expect(find.text('Add Highlight'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      'A test highlight from the reader.',
    );
    await tester.ensureVisible(find.text('Add Highlight'));
    await tester.tap(find.text('Add Highlight'));
    await tester.pump();

    expect(find.text('A test highlight from the reader.'), findsOneWidget);
  });

  testWidgets('shows writer workspace', (tester) async {
    await tester.pumpWidget(const SurrealRapApp());

    final dropdown = find.byType(DropdownButton<int>);
    if (dropdown.evaluate().isNotEmpty) {
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Writer').last);
    } else {
      await tester.tap(find.byIcon(Icons.edit_note_outlined));
    }
    await tester.pumpAndSettle();

    expect(find.text('Novel Studio'), findsOneWidget);
    expect(find.text('Draft Editor'), findsOneWidget);
    expect(find.text('Story Bible'), findsOneWidget);
  });
}
