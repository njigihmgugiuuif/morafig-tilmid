import 'package:flutter/material.dart';

import 'ui/app.dart';
import 'ui/teacher/teacher_portal_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The teacher panel has its own address (`#/teacher`) and its own root; the
  // student app never loads it.
  runApp(isTeacherPortalAddress(Uri.base)
      ? const TeacherPortalApp()
      : const MarafiqApp());
}
