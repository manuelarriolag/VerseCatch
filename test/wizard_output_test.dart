import 'package:flutter_test/flutter_test.dart';
import 'package:versecatch/main.dart';

void main() {
  test('buildOutputContent includes biblical text when requested', () {
    final content = buildOutputContent(
      sourceText: 'Juan 3:16',
      groupedRefs: const [(reference: 'Juan 3:16', count: 1)],
      includeBibleText: true,
      biblicalTexts: const {'Juan 3:16': 'Porque de tal manera amó Dios al mundo.'},
      versionLabel: 'NVI-S',
    );

    expect(content, contains('Citas bíblicas encontradas'));
    expect(content, contains('Juan 3:16'));
    expect(content, contains('Porque de tal manera amó Dios al mundo.'));
    expect(content, contains('Texto escaneado'));
  });

  test('buildOutputContent omits biblical text by default', () {
    final content = buildOutputContent(
      sourceText: 'Juan 3:16',
      groupedRefs: const [(reference: 'Juan 3:16', count: 1)],
      includeBibleText: false,
      biblicalTexts: const {'Juan 3:16': 'Porque de tal manera amó Dios al mundo.'},
      versionLabel: 'NVI-S',
    );

    expect(content, contains('Juan 3:16'));
    expect(content, contains('Juan 3:16'));
    expect(content, isNot(contains('Porque de tal manera amó Dios al mundo.')));
  });

  test('buildCitationsClipboardContent only includes citations and optional biblical text', () {
    final content = buildCitationsClipboardContent(
      groupedRefs: const [(reference: 'Juan 3:16', count: 1)],
      includeBibleText: true,
      biblicalTexts: const {'Juan 3:16': 'Porque de tal manera amó Dios al mundo.'},
      versionLabel: 'NVI-S',
    );

    expect(content, contains('Citas bíblicas encontradas'));
    expect(content, contains('Juan 3:16'));
    expect(content, contains('Porque de tal manera amó Dios al mundo.'));
    expect(content, isNot(contains('Texto escaneado')));
  });

  test('buildScannedResultClipboardContent only includes scanned text and optional biblical text', () {
    final content = buildScannedResultClipboardContent(
      sourceText: 'Juan 3:16',
      groupedRefs: const [(reference: 'Juan 3:16', count: 1)],
      includeBibleText: true,
      biblicalTexts: const {'Juan 3:16': 'Porque de tal manera amó Dios al mundo.'},
      versionLabel: 'NVI-S',
    );

    expect(content, contains('Texto escaneado'));
    expect(content, contains('Juan 3:16'));
    expect(content, contains('Porque de tal manera amó Dios al mundo.'));
    expect(content, isNot(contains('Citas bíblicas encontradas')));
  });
}
