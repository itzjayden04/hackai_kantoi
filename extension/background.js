// Relays requests from the chat pages to the Kantoi desktop app on this
// computer. Messages never go anywhere else.
const APP = 'http://127.0.0.1:47821';

async function call(path, body) {
  const res = await fetch(APP + path, {
    method: body ? 'POST' : 'GET',
    headers: { 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new Error('Kantoi app error ' + res.status);
  return res.json();
}

chrome.runtime.onMessage.addListener((msg, _sender, reply) => {
  call(msg.path, msg.body)
    .then((data) => reply({ ok: true, data }))
    .catch((e) => reply({ ok: false, error: String(e) }));
  return true; // async reply
});

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({ id: 'kantoi-check', title: 'Check with Kantoi', contexts: ['selection', 'link'] });
});

chrome.contextMenus.onClicked.addListener((info) => {
  const text = info.selectionText || info.linkUrl || '';
  if (text) call('/explain', { text, source: 'web' }).catch(() => {});
});
