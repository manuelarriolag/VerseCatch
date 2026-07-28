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

// Helper: enter text and then unfocus to switch to the _RichTextViewer.
Future<void> _enterTextAndUnfocus(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('source-text-field')), text);
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
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

    expect(find.text('Verse Catch'), findsOneWidget);
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

  testWidgets('shows the source selector and text field', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    expect(find.text('Input source'), findsOneWidget);
    expect(find.byKey(const ValueKey('source-text-field')), findsOneWidget);
  });

  testWidgets('references update when text is entered', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('source-text-field')),
      'John 3:16',
    );
    await tester.pumpAndSettle();

    // While editing, the reference appears inside the text field.
    expect(find.text('John 3:16'), findsWidgets);
  });

  testWidgets(
    'switches to rich text viewer with inline tappable reference on unfocus',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
      await tester.pumpAndSettle();

      await _enterTextAndUnfocus(tester, 'John 3:16');

      // TextField is replaced by the rich viewer.
      expect(find.byKey(const ValueKey('source-text-field')), findsNothing);
      // The inline tappable reference widget is present.
      expect(find.byKey(const ValueKey('ref-chip-John 3:16')), findsOneWidget);
      // The inline edit affordance is no longer shown.
      expect(find.text('Tap to edit'), findsNothing);
    },
  );

  testWidgets('shows biblical text when an inline reference is tapped', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    await _enterTextAndUnfocus(tester, 'John 3:16');

    await tester.tap(find.byKey(const ValueKey('ref-chip-John 3:16')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Biblical text'), findsOneWidget);
    expect(find.textContaining('For God so loved the world'), findsOneWidget);
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

    await _enterTextAndUnfocus(tester, 'John 3:16');

    await tester.tap(find.byKey(const ValueKey('ref-chip-John 3:16')));
    await tester.pumpAndSettle();

    // Scroll the bottom ListView until the copy button is visible.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('copy-bible-text-button')),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('copy-bible-text-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(copiedText, isNotNull);
    expect(copiedText, startsWith('John 3:16 (NVI-S)\n'));
    expect(find.byKey(const ValueKey('copied-icon')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
  });

  testWidgets('shows the supported Bible version codes in selector', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    await _enterTextAndUnfocus(tester, 'John 3:16');
    await tester.tap(find.byKey(const ValueKey('ref-chip-John 3:16')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('bible-version-selector-128')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('NVI-S'), findsAtLeastNWidgets(1));
    expect(find.text('NBLA'), findsOneWidget);
  });

  testWidgets('shows Bible version name on wider devices', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    await _enterTextAndUnfocus(tester, 'John 3:16');
    await tester.tap(find.byKey(const ValueKey('ref-chip-John 3:16')));
    await tester.pumpAndSettle();

    expect(
      find.text('(${kSupportedBibleVersions.first.name})'),
      findsOneWidget,
    );
  });

  testWidgets('resizes footer section by dragging split handle', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    await _enterTextAndUnfocus(tester, 'John 3:16');
    await tester.tap(find.byKey(const ValueKey('ref-chip-John 3:16')));
    await tester.pumpAndSettle();

    final textFieldFinder = find.byKey(const ValueKey('biblical-text-field'));
    final beforeSize = tester.getSize(textFieldFinder).height;

    await tester.drag(
      find.byKey(const ValueKey('footer-resize-handle')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();

    final afterSize = tester.getSize(textFieldFinder).height;
    expect(afterSize, isNot(equals(beforeSize)));
  });

  testWidgets('hides header and footer when entering edit mode', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(VerseCatchApp(bibleTextLookup: _fakeBibleLookup));
    await tester.pumpAndSettle();

    await _enterTextAndUnfocus(tester, 'John 3:16');
    await tester.tap(find.byKey(const ValueKey('ref-chip-John 3:16')));
    await tester.pumpAndSettle();

    expect(find.text('Input source'), findsOneWidget);
    expect(find.text('Biblical text'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Input source'), findsNothing);
    expect(find.text('Biblical text'), findsNothing);
    expect(find.byKey(const ValueKey('source-text-field')), findsOneWidget);
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

  test('extractVerseReferences recognizes chapter-only references', () {
    expect(
      extractVerseReferences(
        'salmos 51, Jud 4, Sal 119, judas 4',
      ),
      containsAll(<String>['salmos 51', 'Jud 1:4', 'Sal 119', 'judas 1:4']),
    );
  });
}
