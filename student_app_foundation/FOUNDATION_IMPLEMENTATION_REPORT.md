# FOUNDATION IMPLEMENTATION REPORT

**تاريخ:** 23 سبتمبر 2026

---

## ⚠️ البند الأهم في هذا التقرير — اقرأه قبل أي شيء آخر

قبل كتابة أي سطر كود، فحصتُ بيئة التنفيذ المتاحة لي فعليًا (وليس افتراضيًا):

```
$ which flutter dart
flutter: not found
dart: not found
$ ping pub.dev
ping: not found  → لا اتصال شبكي متاح أصلاً (الشبكة معطَّلة في هذه البيئة)
```

**لا يوجد Flutter SDK ولا Dart SDK مثبَّتان في بيئة التنفيذ المتاحة لي، ولا يوجد اتصال بالإنترنت.** هذا يعني حرفيًا أنني **لا أستطيع**:
- تشغيل `flutter pub get` (يحتاج شبكة لجلب الحزم من pub.dev).
- تشغيل `dart run build_runner build` (المطلوب لتوليد ملفات `*.g.dart` التي تحتاجها Drift لتعمل — كل ملف `part 'xxx.g.dart'` في الكود يشير إلى ملف غير موجود بعد لأنه يُولَّد آليًا).
- تشغيل `flutter test` أو `dart test` فعليًا.
- التأكد أن المشروع "يبني/يعمل" بالمعنى الذي طلبته حرفيًا في شرط الاكتمال.

**هذا Blocker حقيقي في بيئة التنفيذ نفسها، وليس في التصميم أو الكود.** وفقًا لشرطك الصريح في نهاية طلبك — "لا تقل إن Foundation مكتملة لمجرد أن الملفات كُتبت... اعتبرها COMPLETE فقط إذا: التطبيق يبني/يعمل، الاختبارات تمر" — فإن الحالة الصادقة الوحيدة الممكنة هي:

# **الحالة: NOT COMPLETE (بمعيارك الصارم) — الكود مكتوب ومُراجَع يدويًا بعناية، لكنه غير مُتحقَّق منه بالتشغيل الفعلي.**

**ما فعلته للتعويض قدر الإمكان دون SDK:**
- فحص توازن الأقواس آليًا عبر كل الملفات (24 ملف Dart، 1910 سطر) — لا اختلال مكتشَف.
- كتابة ونشغيل فعلي (وليس وصفًا فقط) لسكريبت `tools/check_repository_boundaries.sh` — وهذا فعليًا **اكتشف خطأً حقيقيًا** في التصميم الأول للحارس التنظيمي (تفصيل في القسم 13) وأصلحته، وأعدت تشغيله للتأكد من النجاح.
- مراجعة يدوية دقيقة لكل استيراد (`import`) وكل استخدام لأنواع Drift (`Value`, `Companion.insert`, إلخ) بناءً على معرفتي بواجهة Drift البرمجية، **لكن هذه مراجعة بشرية-نموذجية، وليست تأكيدًا من مُصرِّف (compiler) فعلي.**

**ما لم أفعله ولا أستطيع فعله هنا:** تأكيد أن الكود **يُصرَّف فعليًا بلا أخطاء**، وأن الاختبارات **تمر فعليًا عند التشغيل**.

**الخطوة العملية الوحيدة لإغلاق هذا Blocker:** تشغيل هذا المشروع في بيئة تملك Flutter SDK واتصالاً بالإنترنت — إما جهازك الشخصي، أو **Claude Code** (الذي يعمل بصلاحيات تنفيذ مختلفة وقد يملك وصولاً لشبكة/SDK غير متاح هنا)، ثم تشغيل:
```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
sh tools/check_repository_boundaries.sh
```
وإبلاغي بالنتيجة، أو لصق أي خطأ تصريف يظهر لأصلحه مباشرة.

---

## 1. الملفات التي أُنشئت

مشروع كامل تحت `/mnt/user-data/outputs/student_app_foundation/` (ومضغوط أيضًا كـ `student_app_foundation.zip`):

```
student_app/
├── pubspec.yaml
├── analysis_options.yaml
├── DEVIATIONS.md
├── SOURCE_OF_TRUTH.md
├── tools/check_repository_boundaries.sh
├── lib/
│   ├── database/
│   │   ├── app_database.dart
│   │   ├── migrations/migration_strategy.dart
│   │   └── tables/ (core, curriculum, planning, derived_state, audit, config — 6 ملفات)
│   ├── repositories/ (append_only, event, explanation_and_override, curriculum,
│   │                   mastery, reality_and_prerequisite — 6 ملفات)
│   ├── validation/validators.dart
│   ├── events/event_types.dart
│   ├── export_import/export_import_service.dart
│   └── domain/enums.dart
└── test/
    ├── fixtures/seed_data.dart
    ├── schema_integrity_test.dart
    ├── source_of_truth_and_append_only_test.dart
    ├── curriculum_safety_test.dart
    ├── export_import_test.dart
    └── migration_and_sync_readiness_test.dart
```
**24 ملف Dart، ~1910 سطر إجمالي.**

---

## 2. الجداول الـ34/36 وحالة كل جدول

كل الجداول الـ34 من الـ Schema المعتمد **مكتوبة بالكامل** (36 جدولاً فعليًا، بسبب توحيد `ScheduleEntry`/`StudySession` الموثَّق مسبقًا — مفصَّل في `DEVIATIONS.md`، الانحراف رقم 1). **لا جدول ناقص.** الحالة لكل جدول: **مكتوب، غير مُصرَّف/مُختبَر فعليًا (بسبب Blocker البيئة أعلاه).**

---

## 3. Migrations

`migration_strategy.dart`: `schemaVersion=1`، `onCreate` يبني كل الجداول، `onUpgrade` فارغ حاليًا (لا إصدار سابق) مع **سياسة ترقية موثَّقة بالتفصيل لأي إصدار مستقبلي** (قاعدة عدم حذف بيانات، اختبار إلزامي لكل تحويل بيانات، إلخ).

---

## 4. Repositories

**6 ملفات، تغطي الأنماط الحرجة كلها** (وليس كل الـ 36 جدولاً — التزامًا صريحًا بقيدك "لا تبدأ كل المحركات الآن"، فقط ما يلزم لإثبات صحة أنماط الحماية):
`AppendOnlyRepository` (أساس)، `EventRepository`، `ExplanationRepository`+`HumanOverrideRepository`، `CurriculumRepository` (الحراس الثلاثة)، `MasteryRepository` (Source-of-Truth)، `RealityConstraintRepository`+`PrerequisiteRepository` (إدخال يدوي فقط + كشف الحلقات).

**جداول Derived State المتبقية (Memory, Error, TimeEstimate, Workload, Priority, Recovery, Emergency) لا تملك Repository مخصصًا بعد** — موثَّق صراحة كنطاق هذه المرحلة فقط (بناؤها يترافق مع بناء المحركات نفسها لاحقًا، كما طلبت صراحة عدم البدء بها الآن).

---

## 5. Validators

`validation/validators.dart`: `TaskValidator` (قواعد التقسيم من CI-2)، `PriorityStateValidator` (Invariant #1 وInvariant #16)، `RealityConstraintValidator`. مستقلة تمامًا عن UI كما طُلب.

---

## 6. حماية Append-only

مُطبَّقة **هيكليًا** (`AppendOnlyRepository` لا يملك `update`/`delete` أصلاً كطريقة على النوع، وليس فقط اتفاقًا) + **تنظيميًا** عبر `check_repository_boundaries.sh` المُشغَّل فعليًا وناجح.

---

## 7. تنفيذ حراس المنهج الثلاثة

- **Guard #1 (الإدخال):** `CurriculumRepository.ingestSubjectLoad` — `status` معامل إلزامي غير قابل للحذف.
- **Guard #2 (الاستهلاك):** `getUsableCoefficient` — يرفض `REPEALED` برمي استثناء صريح `PolicyDataGuardViolation` (وليس `null` صامتًا)، ويستبعد `UNKNOWN/CONFLICT/FROZEN` بإرجاع `null`.
- **Guard #3 (الوصول لقاعدة البيانات):** `readRawStatus` منفصل تمامًا عن `getUsableCoefficient`، **لا يُرجع رقمًا أبدًا**.
- **حارس رابع أُضيف فعليًا في هذه المرحلة (لم يكن في المواصفة الأصلية بهذا الشكل):** `check_repository_boundaries.sh` يمنع أي كود خارج `lib/repositories/` من استيراد `curriculum_tables.dart` مباشرة أصلاً — دفاع بنيوي إضافي فوق الثلاثة.

---

## 8. تنفيذ Source-of-Truth

`SOURCE_OF_TRUTH.md` يوثّق كل كيان (Raw/Derived، من يكتب، من يستهلك). مُطبَّق فعليًا في الكود عبر `MasteryRepository.recomputeFrom` (لا يوجد `setProbability` مباشر).

---

## 9. Export/Import

`export_import_service.dart`: تصدير JSON كامل، استيراد مع **Transaction واحدة تلف كل العملية** (فشل أي صف = Rollback كامل تلقائي عبر `db.transaction()`)، فصل صريح بين سياسة `LastWriteWins` (الجداول المتغيرة) وسياسة `Union-never-overwrite` (الجداول Append-only) — كما طلبت في البند 11 بالضبط، غير مُطبَّق عشوائيًا.

---

## 10. استراتيجية Transactions

`export_import_service.dart` يستخدم `db.transaction()` للاستيراد الكامل. **`EventRepository`/`MasteryRepository` الفردية لا تحتاج transaction صريحة إضافية لأنها عمليات ذرية واحدة already، لكن التسلسل الكامل "تسجيل Event ثم تحديث State الناتج عنه" (المذكور في طلبك البند 14) لم يُبنَ بعد كوحدة واحدة — لأنه يتطلب منطق المحرك نفسه (Mastery/Priority Engine) الذي طلبت صراحة عدم بدائه الآن. هذا محدود النطاق عمدًا، وليس نسيانًا.**

---

## 11. الاختبارات (مكتوبة، غير مُشغَّلة فعليًا بسبب Blocker البيئة)

5 ملفات اختبار تغطي الفئات A-G كلها المطلوبة، بما فيها **اختبارات محددة لكل حالة من الحالات الخمس القانونية** (D)، واختبار Rollback عند فشل الاستيراد (E)، واختبار placeholder صريح وموسوم `skip:` لاختبار الترقية v1→v2 (F، لأنه لا يوجد v2 بعد فعليًا — لم أُخترع اختبارًا وهميًا "ناجحًا").

**الاستثناء الوحيد الذي نُفِّذ وشُغِّل فعليًا بنجاح حقيقي:** `tools/check_repository_boundaries.sh` (سكريبت shell خارج نطاق SDK Dart، تمكنت من تشغيله فعليًا في بيئتي).

---

## 12. نتائج الاختبارات

**لا توجد نتائج تشغيل فعلية لملفات `test/*.dart`** — Blocker البيئة (القسم الأهم أعلاه) يمنع ذلك بالكامل. هذه نتيجة سكريبت الحدود فقط (الوحيد القابل للتشغيل فعليًا هنا):
```
Checking append-only table access boundary...
Checking curriculum/policy table access boundary...
OK: repository access boundaries respected.
```

---

## 13. أي Deviations عن الـ Schema

موثَّقة بالكامل في `DEVIATIONS.md` (5 انحرافات، كلها ضرورات تنفيذية موثَّقة بسبب واضح، لا حذف/تقليص). **الأهم للإبلاغ صراحة:** الانحراف رقم 5 — أول نسخة من `check_repository_boundaries.sh` كانت **خاطئة فعليًا** (تمنع حتى ملفات جداول قاعدة البيانات الشرعية من الإشارة لبعضها عبر Foreign Keys)، اكتُشف هذا **بتشغيل السكريبت فعليًا** لا بمراجعة نظرية، وأُصلح وأُعيد التحقق منه بنجاح. هذا مثال حي على قيمة التشغيل الفعلي مقابل المراجعة النظرية فقط — ويُبرز بالضبط سبب صدقي في وصف بقية الكود بأنه "غير مُتحقَّق منه" بدل ادعاء نجاحه.

---

## 14. Technical Debt

- Repository لجداول Derived State المتبقية (Memory, Error, TimeEstimate, Workload, Priority, Recovery, Emergency) — مؤجَّل عمدًا لمرحلة بناء المحركات.
- اختبار الترقية v1→v2 هو placeholder فعلي (`skip:`)، بانتظار وجود v2 حقيقي.
- اختبار `Last-Write-Wins` في `export_import_test.dart` مبسَّط (لا يُنشئ فعليًا ملفي تصدير بطابعين زمنيين منفصلين حقيقيين) — موسوم بتعليق صريح في الكود نفسه يشرح لماذا وما البديل الأكمل المطلوب لاحقًا.
- Partial unique index لـ "طوارئ نشطة واحدة فقط" — منطقي حاليًا (سيُطبَّق في `EmergencyRepository` المستقبلي)، غير مُختبَر بعد لعدم وجود ذلك الـ Repository في هذه المرحلة.

---

## 15. أي Blocker حقيقي

**البلوكر الوحيد والحقيقي هو ما فُصِّل في أعلى هذا التقرير: غياب Flutter/Dart SDK واتصال الشبكة في بيئة التنفيذ المتاحة لي حاليًا.** لا يوجد بلوكر في التصميم نفسه، ولا في منطق الحراس، ولا في بنية البيانات.

---

## 16. NEXT RECOMMENDED STEP

# **NEXT = FIX DATA FOUNDATION (بمعنى ضيق تحديدًا: إغلاق Blocker التحقق، لا إعادة تصميم)**

ليس لأن التصميم أو الكود فيه مشكلة بنيوية معروفة، بل لأن **شرط الاكتمال الذي وضعتَه أنت بنفسك** (التطبيق يبني فعليًا، الاختبارات تمر فعليًا) **لم يتحقق بعد فعليًا في هذه الجلسة**. الخطوة التالية الحرفية:

1. انسخ مجلد `student_app_foundation` (أو استخدم `student_app_foundation.zip` المُرفَق) إلى بيئة تملك Flutter SDK فعليًا — جهازك، أو Claude Code.
2. شغّل: `flutter pub get && dart run build_runner build --delete-conflicting-outputs && flutter test`.
3. أرسل لي أي خطأ تصريف أو اختبار فاشل — سأصلحه فورًا بناءً على رسالة الخطأ الفعلية بدل التخمين.
4. فقط بعد نجاح هذه الخطوات الثلاث فعليًا، يصبح القرار الصحيح `NEXT = BEGIN Priority/Scheduler engines` (المرحلة التالية الحقيقية).

*لم تُكتب UI حقيقية (فقط ما يلزم من DB debug scaffolding ضمنيًا عبر `AppDatabase.forTesting()` للاختبارات). لم تُبنَ كل المحركات. لم يبدأ FSRS/BKT. لم يُعَد بحث تقني واسع. كل هذا كما طلبت بدقة.*
