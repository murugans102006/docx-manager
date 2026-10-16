typedef JsonMap = Map<String, dynamic>;

JsonMap asJson(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  return <String, dynamic>{};
}

String textOf(dynamic value, [String fallback = '']) =>
    value == null ? fallback : '$value';

dynamic unwrap(dynamic value) {
  if (value is Map && value.containsKey('data')) return value['data'];
  return value;
}

List<dynamic> asList(dynamic value) {
  final result = unwrap(value);
  if (result is List) return result;
  final map = asJson(result);
  for (final key in [
    'items',
    'results',
    'requests',
    'users',
    'tasks',
    'documentTypes',
    'notifications',
    'events',
    'history',
    'activity',
    'progress',
    'timeline',
    'data',
  ]) {
    if (map[key] is List) return map[key] as List;
  }
  return const [];
}

enum UserRole { student, coordinator, authority, admin }

UserRole roleFrom(dynamic value) {
  if (value is Map) {
    value = value['name'] ?? value['slug'] ?? value['role'] ?? value['value'];
  }
  final role = textOf(value).toLowerCase().replaceAll('-', '_');
  if (role.contains('coordinator')) return UserRole.coordinator;
  if (role.contains('authority') || role.contains('signatory')) {
    return UserRole.authority;
  }
  if (role.contains('admin')) return UserRole.admin;
  return UserRole.student;
}

extension UserRoleLabel on UserRole {
  String get label => switch (this) {
    UserRole.student => 'Student',
    UserRole.coordinator => 'Coordinator',
    UserRole.authority => 'Authority',
    UserRole.admin => 'Administrator',
  };
}

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.department = '',
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String department;

  factory AppUser.fromJson(JsonMap json) {
    final nested = asJson(json['user']);
    final value = nested.isNotEmpty ? nested : json;
    return AppUser(
      id: textOf(value['id'] ?? value['_id'] ?? value['userId']),
      name: textOf(
        value['name'] ?? value['fullName'] ?? value['username'],
        'User',
      ),
      email: textOf(value['email']),
      role: roleFrom(value['role'] ?? value['userRole']),
      department: textOf(value['department'] ?? value['departmentName']),
    );
  }
}

class DocumentType {
  const DocumentType({
    required this.id,
    required this.name,
    this.description = '',
    this.fields = const [],
  });

  final String id;
  final String name;
  final String description;
  final List<JsonMap> fields;

  factory DocumentType.fromJson(JsonMap json) {
    final rawFields =
        json['fields'] ?? json['requiredFields'] ?? json['formFields'];
    return DocumentType(
      id: textOf(json['id'] ?? json['_id'] ?? json['documentTypeId']),
      name: textOf(json['name'] ?? json['title'] ?? json['type'], 'Document'),
      description: textOf(json['description']),
      fields: rawFields is List
          ? rawFields.map((field) {
              if (field is! String) return asJson(field);
              final label = field
                  .replaceAllMapped(
                    RegExp(r'([a-z0-9])([A-Z])'),
                    (match) => '${match[1]} ${match[2]}',
                  )
                  .replaceAll(RegExp(r'[_-]+'), ' ')
                  .split(' ')
                  .map(
                    (word) => word.isEmpty
                        ? word
                        : '${word[0].toUpperCase()}${word.substring(1)}',
                  )
                  .join(' ');
              return <String, dynamic>{
                'name': field,
                'label': label,
                'required': true,
              };
            }).toList()
          : const [],
    );
  }
}

class DocumentRequest {
  const DocumentRequest(this.json);

  final JsonMap json;
  String get id => textOf(json['id'] ?? json['_id'] ?? json['requestId']);
  String get title {
    if (json['documentTypeName'] != null) {
      return textOf(json['documentTypeName'], 'Document request');
    }
    final documentType = json['documentType'];
    if (documentType is Map) {
      return textOf(
        asJson(documentType)['name'] ?? asJson(documentType)['title'],
        'Document request',
      );
    }
    return textOf(
      documentType ?? json['title'] ?? json['type'],
      'Document request',
    );
  }

  String get status => textOf(json['status'] ?? json['state'], 'submitted');
  String get description => textOf(json['description'] ?? json['purpose']);
  String get createdAt => textOf(json['createdAt'] ?? json['submittedAt']);
  String get studentName => textOf(
    json['studentName'] ??
        asJson(json['student'])['name'] ??
        json['requesterName'],
  );
  String get studentEmail =>
      textOf(json['studentEmail'] ?? asJson(json['student'])['email']);

  factory DocumentRequest.fromJson(JsonMap json) => DocumentRequest(json);
}

class WorkflowOption {
  const WorkflowOption(this.id, this.label);

  final String id;
  final String label;
}

const requestProgressStages = <String>[
  'Submitted',
  'Under review',
  'Information / correction',
  'Document preparation',
  'Signing',
  'Verification',
  'Published',
];

String normalizedStatus(String status) =>
    status.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

int progressIndexForStatus(String status) {
  final normalized = normalizedStatus(status);
  if ([
    'published',
    'completed',
    'complete',
    'delivered',
  ].contains(normalized)) {
    return 6;
  }
  if (normalized.contains('verif')) return 5;
  if (normalized.contains('sign') || normalized.contains('authority')) return 4;
  if (normalized.contains('generat') ||
      normalized.contains('prepar') ||
      normalized.contains('draft')) {
    return 3;
  }
  if (normalized.contains('correction') ||
      normalized.contains('information') ||
      normalized.contains('returned')) {
    return 2;
  }
  if (normalized.contains('review') ||
      normalized.contains('accept') ||
      normalized.contains('processing')) {
    return 1;
  }
  return 0;
}

bool isTerminalStatus(String status) {
  final value = normalizedStatus(status);
  return value.contains('reject') ||
      value.contains('cancel') ||
      value.contains('withdraw');
}

String prettyStatus(String status) {
  if (status.isEmpty) return 'Submitted';
  return status
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}
