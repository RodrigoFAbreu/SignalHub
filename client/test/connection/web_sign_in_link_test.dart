import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/connection/web_sign_in_link.dart';

import '../support/fakes.dart';

void main() {
  String link(Map<String, String> query) => Uri(
    scheme: 'signalhub',
    host: 'signin',
    queryParameters: query,
  ).toString();

  group('WebSignInLink', () {
    test('reads the server and the code of a page\'s link', () {
      final parsed = WebSignInLink.tryParse(
        link({'server': 'https://signalhub.example/', 'code': 'shsc1_abcDEF'}),
      )!;

      expect(parsed.serverUrl, 'https://signalhub.example');
      expect(parsed.code, 'shsc1_abcDEF');
      expect(parsed.toString(), isNot(contains('shsc1_')));
    });

    test('reads the percent-encoded server of the backend\'s own link', () {
      final parsed = WebSignInLink.tryParse(
        'signalhub://signin?server=https%3A%2F%2Fsignalhub.example%2Fhub'
        '&code=shsc1_Qm3Zt9xKc8wYp4aLd2VbNe',
      )!;

      expect(parsed.serverUrl, 'https://signalhub.example/hub');
    });

    for (final text in [
      '',
      'K7Q-4MX',
      pairingUri,
      'https://signalhub.example/',
      'signalhub://signin',
      'signalhub://signin?server=https://signalhub.example',
      'signalhub://signin?server=nope&code=shsc1_x',
      'signalhub://signin?server=https://signalhub.example&code=shpc1_x',
      'signalhub://pair?server=https://signalhub.example&code=shsc1_x',
    ]) {
      test('"$text" is not a sign-in link', () {
        expect(WebSignInLink.tryParse(text), isNull);
      });
    }

    test('names its server however it is spelled', () {
      final parsed = WebSignInLink.tryParse(
        link({'server': 'HTTPS://SignalHub.Example:443/', 'code': 'shsc1_x'}),
      )!;

      expect(parsed.isFor('https://signalhub.example'), isTrue);
      expect(parsed.isFor('https://signalhub.example/'), isTrue);
      expect(parsed.isFor('http://signalhub.example'), isFalse);
      expect(parsed.isFor('https://signalhub.example:8443'), isFalse);
      expect(parsed.isFor('https://signalhub.example/hub'), isFalse);
      expect(parsed.isFor('https://other.example'), isFalse);
    });
  });

  group('WebSignInCode', () {
    test('a code is six characters of the alphabet, in any form', () {
      for (final typed in [
        'K7Q-4MX',
        'k7q-4mx',
        'K7Q4MX',
        ' K7Q 4MX ',
        'k7q4mx',
      ]) {
        expect(WebSignInCode.isPlausible(typed), isTrue, reason: typed);
        expect(WebSignInCode.normalize(typed), 'K7Q4MX');
      }
    });

    test('anything else cannot be a code', () {
      for (final typed in [
        '',
        'K7Q-4M',
        'K7Q-4MXX',
        // I, L, O, 0 and 1 are never in a code.
        'K7Q-4MI',
        'K7Q-4ML',
        'K7Q-4MO',
        'K7Q-4M0',
        'K7Q-4M1',
        'K7Q-4M!',
      ]) {
        expect(WebSignInCode.isPlausible(typed), isFalse, reason: typed);
      }
    });

    test('is complete once it has the length, whichever characters', () {
      expect(WebSignInCode.isComplete('K7Q-4M0'), isTrue);
      expect(WebSignInCode.isComplete('K7Q-4'), isFalse);
      expect(WebSignInCode.isComplete('K7Q-4M!'), isFalse);
    });
  });
}
