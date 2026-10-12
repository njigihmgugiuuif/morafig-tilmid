import 'package:test/test.dart';

import 'package:student_app/database/testing/in_memory_database.dart';
import 'package:student_app/domain/teacher_content_domain.dart';
import 'package:student_app/repositories/teacher_content_repository.dart';
import 'package:student_app/services/teacher_package_service.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
void main() {
  test('the three level paths are named like the school levels', () {
    expect(internalLevelLabel(1), 'الأولى ثانوي');
    expect(internalLevelLabel(2), 'الثانية ثانوي');
    expect(internalLevelLabel(3), 'الثالثة ثانوي');
  });

  test('messages shown to the user never say «حزمة»', () async {
    final db = createInMemoryTeacherDatabase();
    addTearDown(db.close);
    final service = TeacherPackageService(TeacherContentRepository(db));
    for (final text in [
      'not json',
      '{"format":"other"}',
      '{"format":"marafiq.teacher-lesson","formatVersion":99}',
    ]) {
      final preview = await service.inspect(text);
      expect(preview.message.contains('حزمة'), isFalse, reason: text);
      expect(preview.message.contains('الحزمة'), isFalse, reason: text);
    }
  });
}
