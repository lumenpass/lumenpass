import 'package:lumenpass_core/lumenpass_core.dart';
import 'package:test/test.dart';

void main() {
  group('maskCreditCardNumberForDisplay', () {
    test('keeps first 4 and last 3 digits, masks the middle', () {
      final masked = maskCreditCardNumberForDisplay('4111111111111111');
      // 16 digits -> 4 visible + 9 hidden + 3 visible
      expect(masked, '4111${'\u2022' * 9}111');
      expect(masked.substring(0, 4), '4111');
      expect(masked.substring(masked.length - 3), '111');
    });

    test('strips spaces and dashes before masking', () {
      final masked = maskCreditCardNumberForDisplay('4111 1111 1111 1111');
      expect(masked, '4111${'\u2022' * 9}111');
    });

    test('masks Amex (15 digits)', () {
      final masked = maskCreditCardNumberForDisplay('378282246310005');
      // 15 digits -> 4 + 8 hidden + 3
      expect(masked, '3782${'\u2022' * 8}005');
    });

    test('returns short numbers unchanged (<= 7 digits)', () {
      expect(maskCreditCardNumberForDisplay('1234567'), '1234567');
      expect(maskCreditCardNumberForDisplay('123'), '123');
    });

    test('returns empty string for empty input', () {
      expect(maskCreditCardNumberForDisplay(''), '');
    });
  });
}
