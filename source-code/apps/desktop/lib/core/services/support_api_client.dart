import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Result returned by the support contact submission endpoint.
@immutable
class SupportTicketSubmission {
  const SupportTicketSubmission({
    required this.ticketId,
    required this.shortId,
    required this.status,
    required this.priority,
    required this.subject,
    required this.createdAt,
    required this.emailSent,
  });

  final String ticketId;
  final String shortId;
  final String status;
  final String priority;
  final String subject;
  final DateTime createdAt;
  final bool emailSent;
}

class SupportApiException implements Exception {
  const SupportApiException(this.code, this.message, {this.fieldErrors});

  final String code;
  final String message;
  final Map<String, String>? fieldErrors;

  @override
  String toString() => 'SupportApiException($code): $message';
}

/// Thin HTTP client for the LumenPass support module.
///
/// This client only exposes the public, unauthenticated `POST /support/tickets/contact`
/// endpoint used by the Help & contact form in the desktop settings panel.
class SupportApiClient {
  SupportApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        _baseUrl = (baseUrl ?? _defaultBaseUrl).trim() {
    if (!kDebugMode && _baseUrl.isNotEmpty && !_baseUrl.startsWith('https://')) {
      throw StateError(
        'BACKEND_API_URL must use HTTPS in production builds. Got: $_baseUrl',
      );
    }
  }

  static const String _defaultBaseUrl =
      String.fromEnvironment('BACKEND_API_URL');

  final http.Client _http;
  final String _baseUrl;

  bool get isConfigured => _baseUrl.isNotEmpty;

  Uri _uri(String path) {
    if (!isConfigured) {
      throw const SupportApiException(
        'not_configured',
        'BACKEND_API_URL is not set. Configure it in dart_defines.local.json.',
      );
    }
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final suffix = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$suffix');
  }

  Future<SupportTicketSubmission> submitContactTicket({
    required String name,
    required String email,
    required String subject,
    required String message,
    String priority = 'medium',
    String source = 'desktop',
    String? category,
    String? captchaQuestion,
    Object? captchaAnswer,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'email': email,
      'subject': subject,
      'message': message,
      'priority': priority,
      'source': source,
      if (category != null && category.isNotEmpty) 'category': category,
      if (captchaQuestion != null && captchaAnswer != null)
        'captcha': <String, dynamic>{
          'question': captchaQuestion,
          'answer': captchaAnswer,
        },
    };

    http.Response response;
    try {
      response = await _http
          .post(
            _uri('/support/tickets/contact'),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } on SocketException catch (err) {
      throw SupportApiException('network', 'Network error: ${err.message}');
    } on http.ClientException catch (err) {
      throw SupportApiException('network', err.message);
    } catch (err) {
      throw SupportApiException('unknown', err.toString());
    }

    final decoded = _decode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final ticket = decoded is Map<String, dynamic>
          ? decoded['ticket'] as Map<String, dynamic>?
          : null;
      final notification = decoded is Map<String, dynamic>
          ? decoded['notification'] as Map<String, dynamic>?
          : null;
      if (ticket == null) {
        throw const SupportApiException('bad_response', 'Malformed server response.');
      }
      return SupportTicketSubmission(
        ticketId: (ticket['id'] ?? '').toString(),
        shortId: (ticket['shortId'] ?? '').toString(),
        status: (ticket['status'] ?? '').toString(),
        priority: (ticket['priority'] ?? '').toString(),
        subject: (ticket['subject'] ?? '').toString(),
        createdAt: DateTime.tryParse((ticket['createdAt'] ?? '').toString()) ?? DateTime.now(),
        emailSent: notification != null && notification['emailSent'] == true,
      );
    }

    if (response.statusCode == 400) {
      final fieldErrors = <String, String>{};
      String message = 'Please review the form and try again.';
      if (decoded is Map<String, dynamic>) {
        final issues = decoded['message'];
        final issuesList = decoded['issues'];
        if (issues is String) message = issues;
        if (issuesList is List) {
          for (final item in issuesList) {
            if (item is Map && item['field'] is String) {
              fieldErrors[item['field'] as String] =
                  (item['message'] ?? 'Invalid value').toString();
            }
          }
        }
      }
      throw SupportApiException('bad_request', message, fieldErrors: fieldErrors);
    }
    if (response.statusCode == 429) {
      throw const SupportApiException(
        'rate_limited',
        'Too many submissions. Please wait a moment before trying again.',
      );
    }
    if (response.statusCode >= 500) {
      throw SupportApiException(
        'server',
        'Server error (${response.statusCode}). Please try again later.',
      );
    }
    throw SupportApiException(
      'http_${response.statusCode}',
      'Unexpected response (${response.statusCode}).',
    );
  }

  Object? _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  void close() => _http.close();
}
