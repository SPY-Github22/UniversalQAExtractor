import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_qa_extractor/screens/home_screen.dart';

void main() {
  testWidgets('HomeScreen builds correctly and contains text and button', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );

    expect(find.text('Universal QA Extractor Screen Capture'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Start Screen Capture'), findsOneWidget);
  });
}
