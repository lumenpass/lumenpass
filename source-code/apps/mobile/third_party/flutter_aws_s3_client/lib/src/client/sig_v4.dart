import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

const _awsSha256 = 'AWS4-HMAC-SHA256';
const _aws4request = 'aws4_request';
const _aws4 = 'AWS4';

class SigV4 {
  static String generateDatetime() {
    return DateTime.now()
        .toUtc()
        .toString()
        .replaceAll(RegExp(r'\.\d*Z$'), 'Z')
        .replaceAll(RegExp(r'[:-]|\.\d{3}'), '')
        .split(' ')
        .join('T');
  }

  static List<int> hash(List<int> value) {
    return sha256.convert(value).bytes;
  }

  static String hexEncode(List<int> value) {
    return hex.encode(value);
  }

  static List<int> sign(List<int> key, String message) {
    final hmac = Hmac(sha256, key);
    final dig = hmac.convert(utf8.encode(message));
    return dig.bytes;
  }

  static String hashCanonicalRequest(String request) {
    return hexEncode(hash(utf8.encode(request)));
  }

  static String buildCanonicalUri(String uri) {
    return Uri.encodeFull(uri);
  }

  static String buildCanonicalQueryString(Map<String, String>? queryParams) {
    if (queryParams == null) {
      return '';
    }

    final sortedQueryParams = <String>[];
    queryParams.forEach((key, value) {
      sortedQueryParams.add(key);
    });
    sortedQueryParams.sort();

    final canonicalQueryStrings = <String>[];
    sortedQueryParams.forEach((key) {
      canonicalQueryStrings.add(
          '$key=${Uri.encodeQueryComponent(queryParams[key]!).replaceAll('+', "%20")}');
    });

    return canonicalQueryStrings.join('&');
  }

  static String buildCanonicalHeaders(Map<String, String?> headers) {
    final sortedKeys = <String>[];
    headers.forEach((property, _) {
      sortedKeys.add(property);
    });

    var canonicalHeaders = '';
    sortedKeys.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    sortedKeys.forEach((property) {
      canonicalHeaders += '${property.toLowerCase()}:${headers[property]}\n';
    });

    return canonicalHeaders;
  }

  static String buildCanonicalSignedHeaders(Map<String, String?> headers) {
    final sortedKeys = <String>[];
    headers.forEach((property, _) {
      sortedKeys.add(property.toLowerCase());
    });
    sortedKeys.sort();

    return sortedKeys.join(';');
  }

  static String buildStringToSign(
      String datetime, String? credentialScope, String? hashedCanonicalRequest) {
    return '$_awsSha256\n$datetime\n$credentialScope\n$hashedCanonicalRequest';
  }

  static String buildCredentialScope(
      String datetime, String region, String service) {
    return '${datetime.substring(0, 8)}/$region/$service/$_aws4request';
  }

  static String buildCanonicalRequest(
      String? method,
      String path,
      Map<String, String>? queryParams,
      Map<String, String?> headers,
      String payload) {
    final canonicalRequest = [
      method,
      buildCanonicalUri(path),
      buildCanonicalQueryString(queryParams),
      buildCanonicalHeaders(headers),
      buildCanonicalSignedHeaders(headers),
      hexEncode(hash(utf8.encode(payload))),
    ];
    return canonicalRequest.join('\n');
  }

  static String buildAuthorizationHeader(String accessKey,
      String credentialScope, Map<String, String?> headers, String signature) {
    return _awsSha256 +
        ' Credential=' +
        accessKey +
        '/' +
        credentialScope +
        ', SignedHeaders=' +
        buildCanonicalSignedHeaders(headers) +
        ', Signature=' +
        signature;
  }

  static List<int> calculateSigningKey(
      String secretKey, String datetime, String region, String service) {
    return sign(
        sign(
            sign(
                sign(utf8.encode('$_aws4$secretKey'), datetime.substring(0, 8)),
                region),
            service),
        _aws4request);
  }

  static String calculateSignature(List<int> signingKey, String stringToSign) {
    return hexEncode(sign(signingKey, stringToSign));
  }
}
