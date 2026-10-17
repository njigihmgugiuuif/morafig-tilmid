import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

/// STATUS: written without a Dart SDK; verified only by GitHub Actions.
///
/// Source-level contract of the installable app (PWA). It checks the files
/// in web/ that decide whether a browser offers «تثبيت» and whether the
/// offline worker can be built. It does NOT prove an installed app on a real
/// phone: that is tested by hand (and the deploy workflow's offline check
/// opens the built app with the network off in desktop Chromium).
void main() {
  final manifest =
      jsonDecode(File('web/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
  final index = File('web/index.html').readAsStringSync();
  final worker = File('web/mq_sw.js').readAsStringSync();

  group('manifest', () {
    test('names, start page, standalone display, Arabic RTL', () {
      expect(manifest['name'], contains('مرافق التلميذ'));
      expect(manifest['name'], contains('ثانوية رابح بطاط'));
      expect(manifest['short_name'], 'مرافق التلميذ');
      expect(manifest['start_url'], '.');
      expect(manifest['display'], 'standalone');
      expect(manifest['lang'], 'ar');
      expect(manifest['dir'], 'rtl');
      expect(manifest['theme_color'], matches(RegExp(r'^#[0-9A-Fa-f]{6}$')));
      expect(
          manifest['background_color'], matches(RegExp(r'^#[0-9A-Fa-f]{6}$')));
    });

    test('has 192 and 512 icons, plain and maskable, that really exist', () {
      final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
      bool has(String size, {required bool maskable}) => icons.any((i) =>
          i['sizes'] == size &&
          i['type'] == 'image/png' &&
          ((i['purpose'] == 'maskable') == maskable));
      expect(has('192x192', maskable: false), isTrue);
      expect(has('512x512', maskable: false), isTrue);
      expect(has('192x192', maskable: true), isTrue);
      expect(has('512x512', maskable: true), isTrue);

      for (final i in icons) {
        final f = File('web/${i['src']}');
        expect(f.existsSync(), isTrue, reason: '${i['src']} is missing');
        final bytes = f.readAsBytesSync();
        // PNG signature, then IHDR width/height.
        expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final w = ByteData.sublistView(bytes, 16, 20).getUint32(0);
        final h = ByteData.sublistView(bytes, 20, 24).getUint32(0);
        final want = int.parse((i['sizes'] as String).split('x').first);
        expect([w, h], [want, want],
            reason: '${i['src']} is not ${i['sizes']}');
      }
    });
  });

  group('index.html', () {
    test('links the manifest, theme colour and touch icon', () {
      expect(index, contains('rel="manifest" href="manifest.json"'));
      expect(index, contains('name="theme-color"'));
      expect(index, contains('rel="apple-touch-icon"'));
      expect(index, contains('name="viewport"'));
      expect(index, contains(r'<base href="$FLUTTER_BASE_HREF">'));
    });

    test('keeps the Search Console verification tag and the canonical link',
        () {
      expect(index, contains('name="google-site-verification"'));
      expect(index, contains('rel="canonical"'));
    });

    test('registers only OUR worker (the file must carry the marker)', () {
      expect(index, contains("t.indexOf('mq-offline-sw')"));
      expect(index, contains("register('flutter_service_worker.js')"));
      expect(worker, contains('mq-offline-sw'));
    });

    test('offline-ready probe reads the same cache the worker fills', () {
      expect(index, contains('window.mqOfflineReady'));
      final name = RegExp(r"const CACHE = '([^']+)'").firstMatch(worker)!.group(1);
      expect(index, contains("caches.open('$name')"));
    });

    test('keeps the install hooks the app uses', () {
      expect(index, contains('beforeinstallprompt'));
      expect(index, contains('window.mqInstall'));
      expect(index, contains('window.mqIsStandalone'));
    });
  });

  group('offline worker template', () {
    test('keeps the placeholders the deploy step fills', () {
      expect(worker, contains('__MQ_BUILD__'));
      expect(worker, contains('/*MQ_FILES*/'));
    });

    test('handles install, activate and fetch; never touches POST', () {
      expect(worker, contains("addEventListener('install'"));
      expect(worker, contains("addEventListener('activate'"));
      expect(worker, contains("addEventListener('fetch'"));
      expect(worker, contains("req.method !== 'GET'"));
    });

    test('falls back to the saved home page when offline', () {
      expect(worker, contains("SCOPE + 'index.html'"));
    });
  });
}
