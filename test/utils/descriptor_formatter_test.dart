import 'package:flutter_test/flutter_test.dart';
import 'package:deadbolt/widgets/descriptor_span_builder.dart';

void main() {
  group('formatDescriptor', () {
    test('simple multisig alias stays inline', () {
      const input = 'wsh(sortedmulti(2,@Alice,@Bob))#abc123';
      expect(formatDescriptor(input), input);
    });

    test('simple multisig raw stays inline', () {
      const input =
          'wsh(sortedmulti(2,[aabb0011/48h/0h/0h/2h]xpubFoo/<0;1>/*,'
          '[ccdd2233/48h/0h/0h/2h]xpubBar/<0;1>/*))#xyz';
      expect(formatDescriptor(input), input);
    });

    test('or_d with nested and_v breaks correctly', () {
      const input =
          'wsh(or_d(pk(@Alice),and_v(v:pk(@Bob),older(1000))))#abc';
      const expected = 'wsh(or_d(\n'
          '  pk(@Alice),\n'
          '  and_v(\n'
          '    v:pk(@Bob),\n'
          '    older(1000)\n'
          '  )\n'
          '))#abc';
      expect(formatDescriptor(input), expected);
    });

    test('tr with brace set breaks correctly', () {
      const input = 'tr(@unspendable,{pk(@Alice),pk(@Bob)})#abc';
      const expected = 'tr(\n'
          '  @unspendable,\n'
          '  {\n'
          '    pk(@Alice),\n'
          '    pk(@Bob)\n'
          '  }\n'
          ')#abc';
      expect(formatDescriptor(input), expected);
    });

    test('thresh breaks each argument', () {
      const input = 'wsh(thresh(2,pk(@Alice),pk(@Bob),pk(@Charlie)))#abc';
      const expected = 'wsh(thresh(\n'
          '  2,\n'
          '  pk(@Alice),\n'
          '  pk(@Bob),\n'
          '  pk(@Charlie)\n'
          '))#abc';
      expect(formatDescriptor(input), expected);
    });

    test('fingerprint paths not split inside [...]', () {
      const input =
          'wsh(sortedmulti(2,[aabbccdd/84h/0h/0h]xpubFoo/<0;1>/*,'
          '[11223344/84h/0h/0h]xpubBar/<0;1>/*))#check';
      // No formatting expected — sortedmulti is inline
      expect(formatDescriptor(input), input);
    });

    test('checksum preserved verbatim', () {
      const input = 'wsh(or_d(pk(@A),pk(@B)))#deadbeef';
      expect(formatDescriptor(input), endsWith('#deadbeef'));
    });

    test('descriptor without checksum handled', () {
      const input = 'wsh(or_d(pk(@A),pk(@B)))';
      final result = formatDescriptor(input);
      expect(result, isNot(contains('#')));
      expect(result, contains('\n'));
    });

    test('tr without script tree gets breaking newline', () {
      const input = 'tr(@Alice)#abc';
      const expected = 'tr(\n  @Alice\n)#abc';
      expect(formatDescriptor(input), expected);
    });

    test('or_i breaks two arguments', () {
      const input = 'wsh(or_i(pk(@Alice),pk(@Bob)))#abc';
      const expected = 'wsh(or_i(\n'
          '  pk(@Alice),\n'
          '  pk(@Bob)\n'
          '))#abc';
      expect(formatDescriptor(input), expected);
    });

    test('and_b breaks two arguments', () {
      const input = 'wsh(and_b(pk(@Alice),s:pk(@Bob)))#abc';
      const expected = 'wsh(and_b(\n'
          '  pk(@Alice),\n'
          '  s:pk(@Bob)\n'
          '))#abc';
      expect(formatDescriptor(input), expected);
    });

    test('pkh stays inline', () {
      const input = 'pkh(@Alice)#abc';
      expect(formatDescriptor(input), input);
    });

    test('wpkh stays inline', () {
      const input = 'wpkh(@Alice)#abc';
      expect(formatDescriptor(input), input);
    });
  });
}
