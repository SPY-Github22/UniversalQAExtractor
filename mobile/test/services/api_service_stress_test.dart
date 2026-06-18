import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:universal_qa_extractor/services/api_service.dart';

void main() {
  group('ApiService Adversarial and Stress Tests', () {
    const String testIp = '127.0.0.1';
    const String testDeviceId = 'stress-test-device';

    test('ST-01: Adversarial JSON - Root is a List instead of a Map', () async {
      final mockHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode([
            {'status': 'success', 'questions': ['Q1']}
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = ApiService(
        httpClient: mockHttpClient,
        serverIp: testIp,
        deviceId: testDeviceId,
      );

      expect(
        () => apiService.extractQuestions('Hello'),
        throwsA(isA<TypeError>()),
      );
    });

    test('ST-02: Adversarial JSON - questions is a Map instead of a List', () async {
      final mockHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'questions': {'q1': 'What is Flutter?'}
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = ApiService(
        httpClient: mockHttpClient,
        serverIp: testIp,
        deviceId: testDeviceId,
      );

      expect(
        () => apiService.extractQuestions('Hello'),
        throwsA(isA<TypeError>()),
      );
    });

    test('ST-03: Adversarial JSON - questions is a String instead of a List', () async {
      final mockHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'questions': 'Not a list'
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = ApiService(
        httpClient: mockHttpClient,
        serverIp: testIp,
        deviceId: testDeviceId,
      );

      expect(
        () => apiService.extractQuestions('Hello'),
        throwsA(isA<TypeError>()),
      );
    });

    test('ST-04: Adversarial JSON - Missing status key', () async {
      final mockHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'questions': ['Q1']
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = ApiService(
        httpClient: mockHttpClient,
        serverIp: testIp,
        deviceId: testDeviceId,
      );

      expect(
        () => apiService.extractQuestions('Hello'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Failed status: null'))),
      );
    });

    test('ST-05: Adversarial JSON - status is not success', () async {
      final mockHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'error',
            'message': 'Invalid credentials'
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = ApiService(
        httpClient: mockHttpClient,
        serverIp: testIp,
        deviceId: testDeviceId,
      );

      expect(
        () => apiService.extractQuestions('Hello'),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Failed status: error'))),
      );
    });

    test('ST-06: Network - Abrupt connection closure (SocketException)', () async {
      final mockHttpClient = MockClient((request) async {
        throw const SocketException('Connection reset by peer');
      });

      final apiService = ApiService(
        httpClient: mockHttpClient,
        serverIp: testIp,
        deviceId: testDeviceId,
      );

      expect(
        () => apiService.extractQuestions('Hello'),
        throwsA(isA<SocketException>()),
      );
    });

    test('ST-07: Network - HTTP Client Error (ClientException)', () async {
      final mockHttpClient = MockClient((request) async {
        throw http.ClientException('Network connection aborted');
      });

      final apiService = ApiService(
        httpClient: mockHttpClient,
        serverIp: testIp,
        deviceId: testDeviceId,
      );

      expect(
        () => apiService.extractQuestions('Hello'),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('ST-08: Network - 302 Found Redirect', () async {
      final mockHttpClient = MockClient((request) async {
        return http.Response('Redirected', 302);
      });

      final apiService = ApiService(
        httpClient: mockHttpClient,
        serverIp: testIp,
        deviceId: testDeviceId,
      );

      expect(
        () => apiService.extractQuestions('Hello'),
        throwsA(isA<HttpException>().having((e) => e.message, 'message', contains('HTTP Error: 302'))),
      );
    });

    test('ST-09: Network - 401 Unauthorized', () async {
      final mockHttpClient = MockClient((request) async {
        return http.Response('Unauthorized', 401);
      });

      final apiService = ApiService(
        httpClient: mockHttpClient,
        serverIp: testIp,
        deviceId: testDeviceId,
      );

      expect(
        () => apiService.extractQuestions('Hello'),
        throwsA(isA<HttpException>().having((e) => e.message, 'message', contains('HTTP Error: 401'))),
      );
    });

    test('ST-10: Extreme Payload - Very large response payload (10,000 questions)', () async {
      final List<String> largeQuestions = List.generate(10000, (index) => 'Question number $index: ' + 'A' * 100);
      final mockHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'questions': largeQuestions
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = ApiService(
        httpClient: mockHttpClient,
        serverIp: testIp,
        deviceId: testDeviceId,
      );

      final stopwatch = Stopwatch()..start();
      final result = await apiService.extractQuestions('Hello');
      stopwatch.stop();

      expect(result.length, 10000);
      expect(result[9999], contains('Question number 9999:'));
      // Performance sanity check: parsing 10k items should take less than 500ms
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('ST-11: Extreme Payload - Very large request input (1MB text)', () async {
      final String largeInput = 'A' * 1024 * 1024; // 1MB
      final mockHttpClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['text'].length, 1024 * 1024);
        return http.Response(
          jsonEncode({
            'status': 'success',
            'questions': ['Parsed large request successfully']
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = ApiService(
        httpClient: mockHttpClient,
        serverIp: testIp,
        deviceId: testDeviceId,
      );

      final stopwatch = Stopwatch()..start();
      final result = await apiService.extractQuestions(largeInput);
      stopwatch.stop();

      expect(result, ['Parsed large request successfully']);
      // Encoding and parsing 1MB should take less than 1000ms
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('ST-12: Adversarial JSON - questions contains mixed/nested data types', () async {
      final mockHttpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'success',
            'questions': [
              'Valid string question',
              123,
              true,
              null,
              {'nested': 'value'},
              [1, 2, 3]
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiService = ApiService(
        httpClient: mockHttpClient,
        serverIp: testIp,
        deviceId: testDeviceId,
      );

      final result = await apiService.extractQuestions('Hello');
      expect(result, [
        'Valid string question',
        '123',
        'true',
        'null',
        '{nested: value}',
        '[1, 2, 3]'
      ]);
    });
  });
}
