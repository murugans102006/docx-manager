import 'package:college_document_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('request progress', () {
    test('maps API statuses to lifecycle stages', () {
      expect(progressIndexForStatus('submitted'), 0);
      expect(progressIndexForStatus('under_review'), 1);
      expect(progressIndexForStatus('information_requested'), 2);
      expect(progressIndexForStatus('document_generated'), 3);
      expect(progressIndexForStatus('awaiting_signature'), 4);
      expect(progressIndexForStatus('pending_verification'), 5);
      expect(progressIndexForStatus('published'), 6);
    });

    test('identifies terminal states and formats API status values', () {
      expect(isTerminalStatus('rejected'), isTrue);
      expect(isTerminalStatus('cancelled'), isTrue);
      expect(isTerminalStatus('in_progress'), isFalse);
      expect(prettyStatus('pending_verification'), 'Pending Verification');
    });
  });

  test('parses role and request identity from backend-shaped JSON', () {
    final user = AppUser.fromJson({
      'user': {
        'id': 'u-4',
        'fullName': 'A Student',
        'email': 'student@college.edu',
        'role': 'student',
      },
    });
    expect(user.id, 'u-4');
    expect(user.role, UserRole.student);

    final request = DocumentRequest.fromJson({
      'requestId': 'r-1',
      'documentType': {'name': 'Enrollment Certificate'},
      'status': 'under_review',
    });
    expect(request.id, 'r-1');
    expect(request.title, 'Enrollment Certificate');
    expect(request.status, 'under_review');
  });

  test('converts backend required field names into required form fields', () {
    final type = DocumentType.fromJson({
      'id': 'type-1',
      'name': 'Bonafide Certificate',
      'requiredFields': ['studentName', 'purpose'],
    });
    expect(type.fields, [
      {'name': 'studentName', 'label': 'Student Name', 'required': true},
      {'name': 'purpose', 'label': 'Purpose', 'required': true},
    ]);
  });
}
