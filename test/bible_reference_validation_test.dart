import 'package:flutter_test/flutter_test.dart';
import 'package:versecatch/main.dart';

void main() {
  test('extractVerseReferences rejects references with chapter overflow', () {
    final references = extractVerseReferences('John 22:1 and Judas 2:1');

    expect(references, isNot(contains('John 22:1')));
    expect(references, isNot(contains('Judas 2:1')));
  });

  test('extractVerseReferences keeps valid chapter references', () {
    final references = extractVerseReferences('John 21:1 and Revelation 22:21');

    expect(references, contains('John 21:1'));
    expect(references, contains('Revelation 22:21'));
  });

  test('extractVerseReferences keeps single-chapter book chapter-only format', () {
    final references = extractVerseReferences('Judas 25, Filemon 6');

    expect(references, contains('Judas 1:25'));
    expect(references, contains('Filemon 1:6'));
  });
}
