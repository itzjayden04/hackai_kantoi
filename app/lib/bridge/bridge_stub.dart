/// Web builds have no local server; the browser extension needs the desktop app.
Future<void> startBridge() async {}

const bridgePort = 47821;
const bridgeSupported = false;
