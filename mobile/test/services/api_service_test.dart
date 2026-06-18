import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:universal_qa_extractor/services/api_service.dart';

void main() {
  test('TC-T1-F2-01: Successful Text Post', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'status': 'success', 'questions': ['Question summary']}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    final result = await apiService.extractQuestions('Hello');
    expect(result, ['Question summary']);
  });

  test('TC-T1-F2-02: HTTP Request Headers Validation', () async {
    final mockHttpClient = MockClient((request) async {
      expect(request.headers['Content-Type'], 'application/json');
      return http.Response(
        jsonEncode({'status': 'success', 'questions': ['Summary']}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    await apiService.extractQuestions('Hello');
  });

  test('TC-T1-F2-03: JSON Body Encoding', () async {
    final mockHttpClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.containsKey('text'), isTrue);
      expect(body.containsKey('chat'), isTrue);
      expect(body.containsKey('timestamp'), isTrue);
      expect(body.containsKey('device_id'), isTrue);
      expect(body['text'], 'Hello');
      expect(body['device_id'], 'test-device-id');
      return http.Response(
        jsonEncode({'status': 'success', 'questions': ['Summary']}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    await apiService.extractQuestions('Hello');
  });

  test('TC-T1-F2-04: Valid Response Parsing', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'status': 'success', 'questions': ['Valid parsed response']}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    final result = await apiService.extractQuestions('Hello');
    expect(result, ['Valid parsed response']);
  });

  test('TC-T1-F2-05: Base URL Dynamic Configuration', () async {
    final mockHttpClient = MockClient((request) async {
      expect(request.url.toString(), 'http://192.168.1.5:5000/extract');
      return http.Response(
        jsonEncode({'status': 'success', 'questions': ['Summary']}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '192.168.1.5', deviceId: 'test-device-id');
    await apiService.extractQuestions('Hello');
  });

  test('TC-T2-F2-01: Server Internal Error (500)', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response('500 Server Error', 500);
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    expect(
      apiService.extractQuestions('Hello'),
      throwsA(isA<HttpException>().having((e) => e.message, 'message', contains('500'))),
    );
  });

  test('TC-T2-F2-02: Network Timeout', () async {
    final mockHttpClient = MockClient((request) async {
      await Future<void>.delayed(const Duration(seconds: 6));
      return http.Response(
        jsonEncode({'status': 'success', 'questions': ['Summary']}),
        200,
      );
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    expect(
      apiService.extractQuestions('Hello'),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('TC-T2-F2-03: Host Unreachable', () async {
    final mockHttpClient = MockClient((request) async {
      throw const SocketException('Host unreachable');
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: 'invalid-ip', deviceId: 'test-device-id');
    expect(
      apiService.extractQuestions('Hello'),
      throwsA(isA<SocketException>()),
    );
  });

  test('TC-T2-F2-04: Empty Payload Submission', () async {
    int requestCount = 0;
    final mockHttpClient = MockClient((request) async {
      requestCount++;
      return http.Response(
        jsonEncode({'status': 'success', 'questions': ['Summary']}),
        200,
      );
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    
    final result1 = await apiService.extractQuestions('');
    final result2 = await apiService.extractQuestions('   ');

    expect(result1, []);
    expect(result2, []);
    expect(requestCount, 0);
  });

  test('TC-T2-F2-05: Malformed JSON Response', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response(
        'Not a valid JSON string',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    expect(
      apiService.extractQuestions('Hello'),
      throwsA(isA<FormatException>()),
    );
  });
}
