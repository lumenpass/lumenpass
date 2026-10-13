import 'package:flutter_test/flutter_test.dart';
import 'package:lumenpass/features/import/infrastructure/csv_parser.dart';

void main() {
  test('quoted multiline fields stay attached to their CSV row', () {
    const csv = 'Title,Username,Password,Notes,Tags\r\n'
        'First,first@example.test,secret,"First line\r\narchived: false",work\r\n'
        '"Second, item",second@example.test,secret2,"A ""quoted"" note",home\r\n';

    final items = const CsvParser().parse(csv);

    expect(items, hasLength(2));
    expect(items[0].title, 'First');
    expect(items[0].notes, 'First line\r\narchived: false');
    expect(items[0].validationErrors, isEmpty);
    expect(items[1].title, 'Second, item');
    expect(items[1].notes, 'A "quoted" note');
    expect(items[1].validationErrors, isEmpty);
  });
}
