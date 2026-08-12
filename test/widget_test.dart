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
    expect(find.text('Explorar citas'), findsOneWidget);
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

  testWidgets(
    'shows the source selector and the text field after choosing text',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
      await tester.pumpAndSettle();

      expect(find.text('¿Cómo quieres comenzar?'), findsOneWidget);
      await _openTextSource(tester);
      expect(find.byKey(const ValueKey('source-text-field')), findsOneWidget);
    },
  );

  testWidgets('keeps the entered text in review edit mode', (
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

    expect(find.byKey(const ValueKey('review-text-field')), findsNothing);
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();

    final reviewField = find.byKey(const ValueKey('review-text-field'));
    expect(tester.widget<TextField>(reviewField).controller!.text, 'John 3:16');
    expect(find.text('Vista previa de citas bíblicas'), findsNothing);
    expect(find.text('Vista previa'), findsOneWidget);
  });

  testWidgets('keeps review editing and navigation above a mobile keyboard', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    final sourceText = List.generate(
      18,
      (index) => 'Línea ${index + 1}',
    ).join('\n');
    await _enterTextAndAdvance(tester, sourceText);
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();

    final reviewField = find.byKey(const ValueKey('review-text-field'));
    await tester.tap(reviewField);
    tester.view.viewInsets = const FakeViewPadding(bottom: 337);
    await tester.pumpAndSettle();

    await tester.enterText(reviewField, '$sourceText\nÚltima línea modificada');
    await tester.pumpAndSettle();

    const visibleBottom = 844.0 - 337.0;
    final reviewSummary = find.byKey(const ValueKey('review-summary'));
    final backButton = find.widgetWithText(OutlinedButton, 'Atrás');
    final continueButton = find.widgetWithText(FilledButton, 'Continuar');
    expect(reviewSummary, findsOneWidget);
    expect(tester.getBottomRight(reviewField).dy, lessThan(visibleBottom));
    expect(
      tester.getBottomRight(reviewSummary).dx,
      lessThanOrEqualTo(tester.getTopLeft(backButton).dx),
    );
    expect(
      tester.getBottomRight(reviewSummary).dy,
      lessThanOrEqualTo(visibleBottom),
    );
    expect(
      tester.getBottomRight(backButton).dy,
      lessThanOrEqualTo(visibleBottom),
    );
    expect(
      tester.getBottomRight(continueButton).dy,
      lessThanOrEqualTo(visibleBottom),
    );
    expect(
      tester.widget<TextField>(reviewField).controller!.text,
      endsWith('Última línea modificada'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selects, zooms, and continues with an image from the empty frame',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        VerseCatchApp(
          bibleTextLookup: _fakeBibleLookup,
          imageFilePicker: () async => 'assets/images/banner_demo.png',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Elegir una imagen'));
      await tester.pumpAndSettle();
      expect(find.text('Sin imagen'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('continue-selected-image')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('empty-image-picker')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(InteractiveViewer), findsOneWidget);
      final continueButton = find.byKey(
        const ValueKey('continue-selected-image'),
      );
      expect(continueButton, findsOneWidget);
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
    },
  );

  testWidgets('shows OCR overlay immediately and keeps it for at least 6 seconds', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      VerseCatchApp(
        bibleTextLookup: _fakeBibleLookup,
        imageFilePicker: () async => 'assets/images/banner_demo.png',
        ocrTextRecognizer: (imagePath) async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return 'John 3:16';
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Elegir una imagen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('empty-image-picker')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('continue-selected-image')));
    await tester.pump();

    expect(find.byKey(const ValueKey('ocr-scan-overlay')), findsOneWidget);
    expect(find.byKey(const ValueKey('selected-image-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('ocr-hud-panel')), findsOneWidget);
    expect(find.text('Revisar el texto reconocido'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const ValueKey('ocr-scan-overlay')), findsOneWidget);
    expect(find.text('Revisar el texto reconocido'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byKey(const ValueKey('ocr-scan-overlay')), findsOneWidget);
    expect(find.text('Revisar el texto reconocido'), findsNothing);

    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byKey(const ValueKey('ocr-scan-overlay')), findsOneWidget);

    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets('keeps scanning overlay active when OCR runs longer than 6 seconds', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      VerseCatchApp(
        bibleTextLookup: _fakeBibleLookup,
        imageFilePicker: () async => 'assets/images/banner_demo.png',
        ocrTextRecognizer: (imagePath) async {
          await Future<void>.delayed(const Duration(seconds: 8));
          return 'John 3:16';
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Elegir una imagen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('empty-image-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('continue-selected-image')));
    await tester.pump();

    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(const ValueKey('ocr-scan-overlay')), findsOneWidget);
    expect(find.byKey(const ValueKey('selected-image-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('ocr-hud-panel')), findsOneWidget);
    expect(find.text('Revisar el texto reconocido'), findsNothing);

    await tester.pump(const Duration(milliseconds: 2100));
    expect(find.byKey(const ValueKey('ocr-scan-overlay')), findsOneWidget);
    expect(find.text('Revisar el texto reconocido'), findsNothing);

    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const ValueKey('ocr-scan-overlay')), findsOneWidget);

    await tester.pump(const Duration(seconds: 8));
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

  testWidgets('shows detect, explore, and finish after scanning references', (
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
    await tester.tap(find.text('Finalizar'));
    await tester.pumpAndSettle();

    expect(find.text('Exportar texto'), findsNothing);
    final newScanButton = find.widgetWithText(FilledButton, 'Nuevo escaneo');
    expect(newScanButton, findsOneWidget);
    expect(
      find.descendant(
        of: newScanButton,
        matching: find.byIcon(Icons.first_page_rounded),
      ),
      findsOneWidget,
    );
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

  testWidgets('toggles between exclusive review preview and edit modes', (
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
    expect(find.byKey(const ValueKey('review-text-field')), findsNothing);

    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();

    expect(find.text('Vista previa de citas bíblicas'), findsNothing);
    expect(find.byKey(const ValueKey('review-text-field')), findsOneWidget);

    await tester.tap(find.text('Vista previa'));
    await tester.pumpAndSettle();

    expect(find.text('2 citas resaltadas'), findsOneWidget);
    expect(find.text('Vista previa de citas bíblicas'), findsOneWidget);
    expect(find.byKey(const ValueKey('review-text-field')), findsNothing);
  });

  testWidgets('only navigates to completed steps and resets from the header', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Revisar texto'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cómo quieres comenzar?'), findsOneWidget);

    await _enterTextAndAdvance(tester, 'John 3:16');
    expect(find.text('Revisar el texto reconocido'), findsOneWidget);

    await tester.tap(find.text('Explorar citas'));
    await tester.pumpAndSettle();
    expect(find.text('Revisar el texto reconocido'), findsOneWidget);

    await tester.tap(find.text('Elegir origen'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cómo quieres comenzar?'), findsOneWidget);

    expect(find.byIcon(Icons.first_page_rounded), findsOneWidget);
    await tester.tap(find.text('Nuevo escaneo'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cómo quieres comenzar?'), findsOneWidget);
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
