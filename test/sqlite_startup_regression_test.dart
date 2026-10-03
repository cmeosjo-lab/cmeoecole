import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('busy_timeout must use the row-returning Android query API', () {
    final source = File('lib/services/local_store.dart').readAsStringSync();
    expect(source, contains("await db.rawQuery('PRAGMA busy_timeout = 5000')"));
    expect(source, isNot(contains("execute('PRAGMA busy_timeout")));
    expect(source, contains("rawQuery('PRAGMA journal_mode = WAL')"));
    expect(source, contains("rawQuery('PRAGMA quick_check')"));
  });

  test('startup hotfix retains the existing database and schema version', () {
    final source = File('lib/services/local_store.dart').readAsStringSync();
    expect(source, contains('gestcours_v24.db'));
    expect(source, contains('version: 1,'));
    expect(source, isNot(contains('deleteDatabase(')));
    expect(source, isNot(contains('DROP TABLE')));
  });
}
