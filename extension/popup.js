// Shows whether the Kantoi app on this computer is reachable.
chrome.runtime.sendMessage({ path: '/health' }, (r) => {
  const up = !!(r && r.ok);
  document.getElementById('status').className = 'status ' + (up ? 'on' : 'off');
  document.getElementById('msg').textContent = up
    ? 'Protection is on. Open a chat in WhatsApp Web or Telegram Web.'
    : 'The Kantoi app is not running.';
  document.getElementById('steps').hidden = up;
});
