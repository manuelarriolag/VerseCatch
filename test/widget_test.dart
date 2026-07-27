import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:versecatch/main.dart';

void main() {
  testWidgets('shows the VerseCatch home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const VerseCatchApp());
    await tester.pumpAndSettle();

    expect(find.text('VerseCatch'), findsOneWidget);
  });

  testWidgets('shows the source selector and text field',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const VerseCatchApp());
    await tester.pumpAndSettle();

    expect(find.text('Input source'), findsOneWidget);
    expect(find.byKey(const ValueKey('source-text-field')), findsOneWidget);
  });

  testWidgets('references update when text is entered',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const VerseCatchApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('source-text-field')),
      'John 3:16',
    );
    await tester.pumpAndSettle();

    expect(find.text('John 3:16'), findsWidgets);
  });

  test('extractVerseReferences finds scripture references', () {
    expect(
      extractVerseReferences('John 3:16, Romans 8:28, and 1 Cor 13:4-7'),
      containsAll(<String>['John 3:16', 'Romans 8:28', '1 Cor 13:4-7']),
    );
  });

  test('extractVerseReferences tolerates noisy OCR separators', () {
    const ocrText =
        '...justificación por la fe sola (Lc 18 9-14; Rom 4:1-12, 10.1-13; Gal 2:16-21; 3:1-14), '
        'profecías falsas (Mt 7:15; Hch 20.30; 1 Tes 2 1).';

    expect(
      extractVerseReferences(ocrText),
      containsAll(<String>[
        'Lc 18:9-14',
        'Rom 4:1-12',
        'Rom 10:1-13',
        'Gal 2:16-21',
        'Gal 3:1-14',
        'Mt 7:15',
        'Hch 20:30',
        '1 Tes 2:1',
      ]),
    );
  });
}
