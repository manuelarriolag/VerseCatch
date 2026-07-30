import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:versecatch/main.dart';

Future<String?> _fakeBibleLookup(String reference, int bibleVersionId) async {
  if (reference == 'John 3:16') {
    return 'For God so loved the world that he gave his one and only Son, '
        'that whoever believes in him shall not perish but have eternal life.';
  }
  return 'Sample biblical text for version $bibleVersionId';
}

Future<void> _openTextSource(WidgetTester tester) async {
  await tester.tap(find.text('Escribir o pegar texto'));
  await tester.pumpAndSettle();
}

Future<void> _enterTextAndAdvance(WidgetTester tester, String text) async {
  await _openTextSource(tester);
  await tester.enterText(find.byKey(const ValueKey('source-text-field')), text);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continuar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the VerseCatch home screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    expect(find.text('¿Cómo quieres comenzar?'), findsOneWidget);
  });

  testWidgets('shows the app version label and updated step names', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    expect(find.text('Verse Catch v1.0'), findsOneWidget);
    expect(find.text('Detectar citas'), findsOneWidget);
    expect(find.text('Explorar citas'), findsNothing);
  });

  testWidgets('hides history UI when the history feature flag is off', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    expect(find.text('Recent scans'), findsNothing);
    expect(find.byTooltip('Save to history'), findsNothing);
  });

  testWidgets('shows the source selector and the text field after choosing text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    expect(find.text('¿Cómo quieres comenzar?'), findsOneWidget);
    await _openTextSource(tester);
    expect(find.byKey(const ValueKey('source-text-field')), findsOneWidget);
  });

  testWidgets('keeps the entered text on the review step', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    await _openTextSource(tester);
    await tester.enterText(
      find.byKey(const ValueKey('source-text-field')),
      'John 3:16',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    final reviewField = find.byType(TextField).last;
    expect(tester.widget<TextField>(reviewField).controller!.text, 'John 3:16');
  });

  testWidgets('moves to review step after entering text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    await _enterTextAndAdvance(tester, 'John 3:16');

    expect(find.text('Revisar el texto reconocido'), findsOneWidget);
    expect(find.text('Vista previa de citas bíblicas'), findsOneWidget);
  });

  testWidgets('shows the detect and explore steps after scanning references', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    await _enterTextAndAdvance(tester, 'John 3:16');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('¡Encontramos 1 citas!'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Copiar versículo'), findsOneWidget);
  });

  testWidgets('copies the selected biblical text and shows feedback', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            final arguments = methodCall.arguments as Map<Object?, Object?>?;
            copiedText = arguments?['text'] as String?;
            return null;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    await _enterTextAndAdvance(tester, 'John 3:16');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Copiar versículo'));
    await tester.pumpAndSettle();

    expect(copiedText, isNotNull);
    expect(copiedText, startsWith('John 3:16'));
  });

  testWidgets('shows the supported Bible version codes in the selector', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    await _enterTextAndAdvance(tester, 'John 3:16');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('NVI-S'));
    await tester.pumpAndSettle();

    expect(find.text('NBLA'), findsOneWidget);
  });

  testWidgets('keeps the version selector visible on wider screens', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    await _enterTextAndAdvance(tester, 'John 3:16');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<int>), findsOneWidget);
    expect(find.text('NVI-S'), findsOneWidget);
  });

  testWidgets('shows the review preview and lets the user hide it', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    await _openTextSource(tester);
    await tester.enterText(
      find.byKey(const ValueKey('source-text-field')),
      'John 3:16 and Romans 8:28',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    expect(find.text('Vista previa de citas bíblicas'), findsOneWidget);

    await tester.tap(find.byTooltip('Volver a revisar citas'));
    await tester.pumpAndSettle();

    expect(find.text('2 citas resaltadas'), findsOneWidget);
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

  test('extractVerseReferences ignores leading noise before a valid book', () {
    expect(extractVerseReferences('principal Efe 3:3'), contains('Efe 3:3'));
    expect(
      extractVerseReferences('principal Efe 3:3'),
      isNot(contains('principal Efe 3:3')),
    );

    expect(extractVerseReferences('principal. Efe 3:3'), contains('Efe 3:3'));
    expect(
      extractVerseReferences('principal. Efe 3:3'),
      isNot(contains('principal. Efe 3:3')),
    );
  });
}
