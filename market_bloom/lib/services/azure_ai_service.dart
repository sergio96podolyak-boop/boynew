import 'dart:convert';
import 'package:http/http.dart' as http;

class AzureAiService {
  AzureAiService({
    http.Client? client,
  }) : _client = client ?? http.Client();

  static final Uri _endpoint = Uri.parse(
    'https://pomarket-mobile-review.pomarket-sergio96.workers.dev/api/ai',
  );

  final http.Client _client;

  Future<String?> ask(String message) async {
    try {
      final response = await _client
          .post(
            _endpoint,
            headers: const {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'message': message,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final data = jsonDecode(response.body);
      final output = data['output'];

      return output is String && output.trim().isNotEmpty
          ? output.trim()
          : null;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
