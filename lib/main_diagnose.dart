// اختبار حاسم واحد فقط: هل يعمل بناء Flutter المنفصل إطلاقًا؟
// لا يستورد أي كود متعلق بقاعدة البيانات أو drift أو AppDatabase عمدًا،
// ليكون الاختبار خاليًا من أي متغير آخر. نتيجته قاطعة:
// - إن ظهر النص الأحمر: آلية النشر سليمة، والمشكلة في كود قاعدة البيانات.
// - إن بقيت الدائرة الزرقاء فقط: المشكلة في آلية النشر نفسها، لا في drift.
import 'package:flutter/material.dart';

void main() {
  runApp(const _Step0App());
}

class _Step0App extends StatelessWidget {
  const _Step0App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.red,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'المرحلة صفر تعمل\n\n'
              'هذا يثبت أن آلية النشر المنفصلة سليمة تمامًا،\n'
              'ولا علاقة لأي تعليق بقاعدة البيانات هنا إطلاقًا.\n'
              'إن كنتِ تريَن هذا النص فالمشكلة في drift فقط.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
