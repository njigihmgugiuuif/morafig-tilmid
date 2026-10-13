import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/student_setup_store.dart';
import '../../services/teacher_session.dart';
import '../design/primitives.dart';
import '../design/states.dart';
import '../design/tokens.dart';
import '../reality/reality_hub_screen.dart';
import '../state/app_state.dart';

/// Settings section: edit the school year and stream any time, open the
/// commitments screen, and reset ONLY the year/stream (nothing else).
///
/// Year and stream live in the device's own storage (see [StudentSetup]);
/// commitments live in the weekly template that the planner already reads.
class StudySetupSection extends StatefulWidget {
  const StudySetupSection({super.key, KeyValueStore? store}) : _store = store;
  final KeyValueStore? _store;

  @override
  State<StudySetupSection> createState() => _StudySetupSectionState();
}

class _StudySetupSectionState extends State<StudySetupSection> {
  late final StudentSetupStore _store =
      StudentSetupStore(widget._store ?? SharedPrefsKeyValueStore());
  final _track = TextEditingController();
  int? _year;
  bool _loaded = false;
  String _savedTrack = '';
  int? _savedYear;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _track.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await _store.read();
    if (!mounted) return;
    setState(() {
      _year = _savedYear = s.year;
      _track.text = _savedTrack = s.track;
      _loaded = true;
    });
  }

  bool get _dirty =>
      _year != _savedYear || _track.text.trim() != _savedTrack;

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    final app = context.read<AppState>();
    final setup = StudentSetup(year: _year, track: _track.text.trim());
    await _store.save(setup);
    if (setup.year != null) app.autoSync.trigger(force: true);
    if (!mounted) return;
    setState(() {
      _savedYear = setup.year;
      _savedTrack = setup.track;
    });
    _snack('تم حفظ سنتك وشعبتك.');
  }

  Future<void> _resetSetup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة إعداد سنتي وشعبتي'),
        content: const Text(
            'سنمسح سنتك وشعبتك فقط، لتختارهما من جديد. لن يُمسح أي شيء آخر: '
            'لا مهامك ولا التزاماتك ولا دروسك ولا تقدّمك.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('امسح السنة والشعبة')),
        ],
      ),
    );
    if (ok != true) return;
    await _store.clear();
    if (!mounted) return;
    setState(() {
      _year = _savedYear = null;
      _track.text = _savedTrack = '';
    });
    _snack('مُسحت السنة والشعبة. اختر من جديد متى شئت.');
  }

  @override
  Widget build(BuildContext context) {
    final mq = context.mq;
    if (!_loaded) return const MqLoadingCard(lines: 3);
    return MqCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('السنة الدراسية',
              style: MqType.body
                  .copyWith(color: mq.ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var y = 1; y <= 3; y++)
                ChoiceChip(
                  label: Text(const [
                    'الأولى ثانوي',
                    'الثانية ثانوي',
                    'الثالثة ثانوي'
                  ][y - 1]),
                  selected: _year == y,
                  onSelected: (_) => setState(() => _year = y),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _track,
            textAlign: TextAlign.right,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'الشعبة أو القسم (اكتبها بنفسك)',
              prefixIcon: Icon(Icons.school_outlined),
            ),
          ),
          MqButton(
            label: 'حفظ السنة والشعبة',
            icon: Icons.save_outlined,
            block: true,
            onPressed: _dirty ? _save : null,
          ),
          const SizedBox(height: 16),
          Text('الأوقات التي تكون فيها مشغولًا',
              style: MqType.body
                  .copyWith(color: mq.ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('لا تبني الخطة على هذه الأوقات. عدّلها أو أضف إليها متى شئت.',
              style: MqType.small.copyWith(color: mq.ink2)),
          const SizedBox(height: 8),
          MqButton(
            label: 'التزاماتي وأوقاتي',
            icon: Icons.event_busy_outlined,
            kind: MqButtonKind.secondary,
            block: true,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                  builder: (_) => const RealityHubScreen()),
            ),
          ),
          const SizedBox(height: 8),
          MqButton(
            label: 'أعد إعداد سنتي وشعبتي',
            icon: Icons.restart_alt,
            kind: MqButtonKind.ghost,
            block: true,
            onPressed: _resetSetup,
          ),
        ],
      ),
    );
  }
}
