/// What the «تثبيت التطبيق» button should do, decided from facts the browser
/// reports. Pure and platform-free so it can be tested without a browser.
///
/// Browsers differ: only Chromium-based browsers (Chrome, Edge, Samsung
/// Internet, Opera) offer a real install prompt (`beforeinstallprompt`).
/// iPhone/iPad Safari has no prompt at all (the user adds the page from the
/// Share sheet). Firefox and others vary. So the button never pretends:
/// it runs the real prompt only when the browser handed one over, and
/// otherwise explains the manual route.
enum InstallStage {
  /// Not a web build, or already running as an installed app: no button.
  hidden,

  /// The browser gave us its install prompt: the button runs it.
  promptable,

  /// No prompt available: the button shows short manual steps.
  manual,

  /// iPhone/iPad: the button shows the Share-sheet steps.
  iosManual,

  /// Installed during this visit: the button turns into a calm status.
  installed,
}

InstallStage decideInstallStage({
  required bool isWeb,
  required bool standalone,
  required bool promptAvailable,
  required bool installedThisVisit,
  required bool ios,
}) {
  if (!isWeb) return InstallStage.hidden;
  if (standalone) return InstallStage.hidden;
  if (installedThisVisit) return InstallStage.installed;
  if (promptAvailable) return InstallStage.promptable;
  return ios ? InstallStage.iosManual : InstallStage.manual;
}

/// Short Arabic steps for the manual route.
String installManualSteps(InstallStage stage) {
  switch (stage) {
    case InstallStage.iosManual:
      return 'في آيفون وآيباد: افتح الصفحة في Safari، اضغط زر المشاركة، '
          'ثم «إضافة إلى الشاشة الرئيسية».';
    case InstallStage.manual:
      return 'من قائمة المتصفح (⋮ أو ⋯) اختر «تثبيت التطبيق» أو «إضافة إلى '
          'الشاشة الرئيسية». إن لم تجدها فافتح الصفحة في Chrome.';
    default:
      return '';
  }
}
