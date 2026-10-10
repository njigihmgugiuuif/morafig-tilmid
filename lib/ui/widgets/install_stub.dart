/// Non-web platforms: there is nothing to install from the browser.
bool canPromptInstall() => false;
bool isStandalone() => false;
Future<bool> promptInstall() async => false;
