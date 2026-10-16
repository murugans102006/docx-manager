import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ApiConfig {
  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api',
  );
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class UploadFile {
  const UploadFile({required this.name, this.path, this.bytes});

  final String name;
  final String? path;
  final List<int>? bytes;
}

class ApiClient {
  ApiClient({
    http.Client? client,
    FlutterSecureStorage? storage,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'auth_token';
  static const _baseUrlKey = 'api_base_url';
  final http.Client _client;
  final FlutterSecureStorage _storage;
  final Duration timeout;
  String baseUrl = ApiConfig.defaultBaseUrl;
  String? _token;

  String? get token => _token;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = (prefs.getString(_baseUrlKey) ?? ApiConfig.defaultBaseUrl)
        .trim()
        .replaceAll(RegExp(r'/+$'), '');
    _token = await _storage.read(key: _tokenKey);
  }

  Future<void> setBaseUrl(String value) async {
    final normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        !['http', 'https'].contains(uri.scheme)) {
      throw const ApiException('Enter a valid http:// or https:// API URL.');
    }
    baseUrl = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, normalized);
  }

  Future<void> saveToken(String token) async {
    _token = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clearToken() async {
    _token = null;
    await _storage.delete(key: _tokenKey);
  }

  Uri _uri(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized');
  }

  Map<String, String> _headers({bool jsonContent = true}) => {
    if (jsonContent) 'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [JsonMap body = const {}]) =>
      _send('POST', path, body: body);
  Future<dynamic> patch(String path, [JsonMap body = const {}]) =>
      _send('PATCH', path, body: body);

  Future<dynamic> _send(String method, String path, {JsonMap? body}) async {
    try {
      final uri = _uri(path);
      late http.Response response;
      switch (method) {
        case 'GET':
          response = await _client
              .get(uri, headers: _headers())
              .timeout(timeout);
        case 'POST':
          response = await _client
              .post(uri, headers: _headers(), body: jsonEncode(body ?? {}))
              .timeout(timeout);
        case 'PATCH':
          response = await _client
              .patch(uri, headers: _headers(), body: jsonEncode(body ?? {}))
              .timeout(timeout);
        default:
          throw const ApiException('Unsupported API operation.');
      }
      return _decodeResponse(response);
    } on TimeoutException {
      throw const ApiException(
        'The server took too long to respond. Please try again.',
      );
    } on SocketException {
      throw const ApiException(
        'Could not connect. Check the API URL and network.',
      );
    } on http.ClientException {
      throw const ApiException('Network request failed. Please try again.');
    } on FormatException {
      throw const ApiException('The server returned an invalid response.');
    }
  }

  dynamic _decodeResponse(http.Response response) {
    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = response.body;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = asJson(decoded);
      final error = asJson(body['error']);
      final message = textOf(
        error['message'] ?? body['message'] ?? body['detail'],
        'Request failed (${response.statusCode}).',
      );
      throw ApiException(message, statusCode: response.statusCode);
    }
    return decoded;
  }

  Future<dynamic> multipart(
    String path, {
    required Map<String, String> fields,
    Map<String, List<UploadFile>> files = const {},
  }) async {
    try {
      final request = http.MultipartRequest('POST', _uri(path));
      if (_token != null) {
        request.headers['Authorization'] = 'Bearer $_token';
      }
      request.fields.addAll(fields);
      for (final entry in files.entries) {
        for (final file in entry.value) {
          if (!kIsWeb && file.path != null && file.path!.isNotEmpty) {
            request.files.add(
              await http.MultipartFile.fromPath(
                entry.key,
                file.path!,
                filename: file.name,
              ),
            );
          } else if (file.bytes != null) {
            request.files.add(
              http.MultipartFile.fromBytes(
                entry.key,
                file.bytes!,
                filename: file.name,
              ),
            );
          } else {
            throw ApiException(
              'The selected file "${file.name}" is not available for upload. Please choose it again.',
            );
          }
        }
      }
      final streamed = await _client.send(request).timeout(timeout);
      return _decodeResponse(
        await http.Response.fromStream(streamed).timeout(timeout),
      );
    } on TimeoutException {
      throw const ApiException(
        'The upload timed out. Check your connection and try again.',
      );
    } on SocketException {
      throw const ApiException(
        'Could not connect. Check the API URL and network.',
      );
    } on http.ClientException {
      throw const ApiException('Network request failed. Please try again.');
    }
  }

  Future<JsonMap> login(String email, String password) async {
    final result = asJson(
      await post('/auth/login', {'email': email, 'password': password}),
    );
    final data = asJson(unwrap(result));
    final token = textOf(
      result['token'] ??
          data['token'] ??
          result['accessToken'] ??
          data['accessToken'],
    );
    if (token.isEmpty)
      throw const ApiException('The response did not include an access token.');
    await saveToken(token);
    return data;
  }

  Future<JsonMap> register(JsonMap values) async {
    final result = asJson(await post('/auth/register', values));
    final data = asJson(unwrap(result));
    final token = textOf(
      result['token'] ?? data['token'] ?? result['accessToken'],
    );
    if (token.isNotEmpty) await saveToken(token);
    return data;
  }

  Future<void> logout() async {
    try {
      await post('/auth/logout');
    } finally {
      await clearToken();
    }
  }

  Future<dynamic> fetchMe() => get('/auth/me');
  Future<dynamic> forgotPassword(String email) =>
      post('/auth/forgot-password', {'email': email});
  Future<dynamic> resetPassword(String email, String code, String password) =>
      post('/auth/reset-password', {
        'email': email,
        'token': code,
        'password': password,
      });

  Future<List<dynamic>> documentTypes() async =>
      asList(await get('/document-types'));
  Future<List<dynamic>> templates({String? documentTypeId}) async {
    final query = documentTypeId == null || documentTypeId.isEmpty
        ? ''
        : '?documentType=${Uri.encodeQueryComponent(documentTypeId)}';
    return asList(await get('/templates$query'));
  }

  Future<List<dynamic>> myRequests() async => asList(await get('/requests/my'));
  Future<dynamic> requestProgress(String id) => get('/requests/$id/progress');
  Future<dynamic> requestHistory(String id) => get('/requests/$id/history');
  Future<List<dynamic>> coordinatorRequests() async =>
      asList(await get('/coordinator/requests'));
  Future<dynamic> coordinatorStats() => get('/coordinator/stats');
  Future<List<dynamic>> authorityTasks() async =>
      asList(await get('/authority/tasks'));
  Future<dynamic> authorityTask(String id) => get('/authority/tasks/$id');
  Future<List<dynamic>> notifications() async =>
      asList(await get('/notifications'));
  Future<dynamic> markNotificationRead(String id) =>
      patch('/notifications/$id/read');
  Future<List<dynamic>> users() async => asList(await get('/admin/users'));
  Future<dynamic> updateUser(String id, JsonMap changes) =>
      patch('/admin/users/$id', changes);

  Future<dynamic> createRequest({
    required String documentTypeId,
    required JsonMap fields,
    required List<UploadFile> supportingFiles,
  }) => multipart(
    '/requests',
    fields: {'documentTypeId': documentTypeId, 'fields': jsonEncode(fields)},
    files: {'supportingFiles': supportingFiles},
  );

  Future<dynamic> action(
    String requestId,
    String action, [
    JsonMap body = const {},
  ]) => post('/requests/$requestId/$action', body);

  Future<dynamic> uploadAction(
    String requestId,
    String action, {
    required String fileField,
    required UploadFile file,
    JsonMap fields = const {},
  }) => multipart(
    '/requests/$requestId/$action',
    fields: fields.map(
      (key, value) =>
          MapEntry(key, value is String ? value : jsonEncode(value)),
    ),
    files: {
      fileField: [file],
    },
  );

  Future<dynamic> uploadSignedDocument(
    String taskId,
    UploadFile file, {
    String note = '',
  }) => multipart(
    '/authority/tasks/$taskId/upload-signed-document',
    fields: {'message': note},
    files: {
      'file': [file],
    },
  );

  Future<dynamic> returnAuthorityTask(String taskId, String reason) => post(
    '/authority/tasks/$taskId/return-for-correction',
    {'message': reason},
  );

  Future<File> downloadFile(
    String versionId, {
    bool preview = false,
    String? suggestedName,
  }) async {
    final endpoint = preview ? 'preview' : 'download';
    try {
      final response = await _client
          .get(
            _uri('/files/$versionId/$endpoint'),
            headers: {if (_token != null) 'Authorization': 'Bearer $_token'},
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _decodeResponse(response);
        throw ApiException('Download failed (${response.statusCode}).');
      }
      final directory = await getApplicationDocumentsDirectory();
      final name = suggestedName?.replaceAll(RegExp(r'[^\w.\- ]'), '_');
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        '${name?.isNotEmpty == true ? name : 'document-$versionId'}',
      );
      return file.writeAsBytes(response.bodyBytes, flush: true);
    } on TimeoutException {
      throw const ApiException('The download timed out. Please try again.');
    } on SocketException {
      throw const ApiException('Could not connect to download this document.');
    } on http.ClientException {
      throw const ApiException('Download failed. Please try again.');
    }
  }
}
