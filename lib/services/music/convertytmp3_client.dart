import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class Convertytmp3Client {
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Origin': 'https://convertytmp3.org',
    'Referer': 'https://convertytmp3.org/',
  };

  static Future<String?> getStreamUrl(String videoId) async {
    try {
      final authUrl = Uri.parse(
        'https://epsilon.epsiloncloud.org/api/v1/auth?_=${DateTime.now().millisecondsSinceEpoch}',
      );
      final authRes = await http
          .get(authUrl, headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (authRes.statusCode != 200) return null;

      final authJson = jsonDecode(authRes.body);
      final key = authJson['key'] as String?;
      if (key == null) return null;

      final authHeaders = Map<String, String>.from(_headers);
      authHeaders['Authorization'] = 'Bearer $key';

      final initUrl = Uri.parse(
        'https://epsilon.epsiloncloud.org/api/v1/init?_=${DateTime.now().millisecondsSinceEpoch}',
      );
      final initRes = await http
          .get(initUrl, headers: authHeaders)
          .timeout(const Duration(seconds: 6));
      if (initRes.statusCode != 200) return null;

      final initJson = jsonDecode(initRes.body);
      final convertURLStr = initJson['convertURL'] as String?;
      if (convertURLStr == null) return null;

      String currentConvertUrl =
          '$convertURLStr&v=$videoId&f=mp3&_=${DateTime.now().millisecondsSinceEpoch}';
      Map<String, dynamic>? convertJson;

      for (int i = 0; i < 5; i++) {
        final res = await http
            .get(Uri.parse(currentConvertUrl), headers: authHeaders)
            .timeout(const Duration(seconds: 6));
        if (res.statusCode != 200) return null;

        try {
          convertJson = jsonDecode(res.body);
        } catch (_) {
          return null;
        }

        if (convertJson != null &&
            convertJson['redirect'] == 1 &&
            convertJson['redirectURL'] != null &&
            (convertJson['redirectURL'] as String).isNotEmpty) {
          currentConvertUrl = convertJson['redirectURL'] as String;
        } else {
          break;
        }
      }

      if (convertJson == null) return null;

      String? dlUrl = convertJson['downloadURL'] as String?;
      final progressUrl = convertJson['progressURL'] as String?;

      if ((dlUrl == null || dlUrl.isEmpty) &&
          progressUrl != null &&
          progressUrl.isNotEmpty) {
        int status = 0;
        int polls = 0;
        while (status != 3) {
          polls++;
          if (polls > 10) return null;
          await Future.delayed(const Duration(milliseconds: 1200));
          final progRes = await http
              .get(Uri.parse(progressUrl), headers: authHeaders)
              .timeout(const Duration(seconds: 5));
          if (progRes.statusCode != 200) return null;

          Map<String, dynamic>? progJson;
          try {
            progJson = jsonDecode(progRes.body);
          } catch (_) {
            return null;
          }

          if (progJson != null) {
            status = progJson['status'] as int? ?? 0;
            if (status == 3) {
              dlUrl = progJson['downloadURL'] as String?;
              break;
            } else if (status < 0) {
              return null;
            }
          }
        }
      }

      if (dlUrl != null && dlUrl.isNotEmpty) {
        return dlUrl;
      }
    } catch (e) {
      debugPrint('Convertytmp3Client failed: $e');
    }
    return null;
  }
}
