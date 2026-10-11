import 'package:flutter_test/flutter_test.dart';

import 'package:student_app/ui/teacher/teacher_portal_app.dart';

void main() {
  test('the teacher panel has its own address; the student address does not',
      () {
    expect(
        isTeacherPortalAddress(
            Uri.parse('https://x.github.io/morafig-tilmid/#/teacher')),
        isTrue);
    expect(isTeacherPortalAddress(Uri.parse('https://x/#/teacher/')), isTrue);
    expect(isTeacherPortalAddress(Uri.parse('https://x/morafig-tilmid/')),
        isFalse);
    expect(isTeacherPortalAddress(Uri.parse('https://x/#/today')), isFalse);
    expect(isTeacherPortalAddress(Uri.parse('https://x/#/teachers')), isFalse);
  });
}
