import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

abstract class IApiService {
  Future<List<String>> extractQuestions(String text);
}

class ApiService implements IApiService {
  final http.Client httpClient;
  final String serverIp;
  final String deviceId;

  ApiService({
    required this.httpClient,
    required this.serverIp,
    required this.deviceId,
  });

  @override
  Future<List<String>> extractQuestions(String text) async {
    // TC-T2-F2-04: Short-circuit empty/whitespace payloads
    if (text.trim().isEmpty) {
      return [];
    }

    final Uri url = Uri.parse('http://$serverIp:5000/extract');
    
    try {
      final response = await httpClient.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': text,
          'chat': text,
          'timestamp': DateTime.now().toIso8601String(),
          'device_id': deviceId,
        }),
      ).timeout(const Duration(seconds: 5)); // TC-T2-F2-02: 5s limit

      if (response.statusCode == 200) {
        // TC-T1-F2-04 / TC-T2-F2-05: Parsing response / malformed JSON
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          final List<dynamic>? questionsJson = data['questions'];
          if (questionsJson != null) {
            return questionsJson.map((q) => q.toString()).toList();
          }
          return [];
        } else {
          throw Exception('Failed status: ${data['status']}');
        }
      } else if (response.statusCode == 500) {
        // TC-T2-F2-01: Server Internal Error
        throw HttpException('Server Error: ${response.statusCode}');
      } else {
        throw HttpException('HTTP Error: ${response.statusCode}');
      }
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } on FormatException {
      rethrow;
    }
  }
}
