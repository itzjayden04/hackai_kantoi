// Kantoi content script: watches the open chat in WhatsApp Web or Telegram
// Web, scores each incoming message through the Kantoi app on this computer,
// and shows a quiet badge plus a conversation-risk panel.
(() => {
  const LABELS = { safe: 'Looks safe', caution: 'Be careful', suspicious: 'Suspicious', danger: 'Very likely a scam' };
  const COLORS = { safe: '#15803d', caution: '#b45309', suspicious: '#ea580c', danger: '#dc2626' };

  // ---- Site adapters -------------------------------------------------------
  const textOf = (el) => (el ? (el.innerText || el.textContent || '').trim() : '');

  const adapters = {
    whatsapp: {
      source: 'whatsapp',
      chatTitle() {
        const h = document.querySelector('#main header');
        if (!h) return null;
        const t = h.querySelector('span[title]') || h.querySelector('span[dir="auto"]');
        return t ? (t.getAttribute('title') || textOf(t)) : null;
      },
      messages() {
        return [...document.querySelectorAll('#main div.message-in, #main div.message-out')].map((el) => {
          const pre = el.querySelector('[data-pre-plain-text]')?.getAttribute('data-pre-plain-text') || '';
          const textEl = el.querySelector('span.selectable-text') || el.querySelector('.copyable-text span[dir]');
          const m = pre.match(/\]\s*([^:]+):\s*$/);
          return {
            el,
            anchor: textEl?.closest('.copyable-text') || textEl || el,
            text: textOf(textEl),
            sender: m ? m[1].trim() : null,
            fromMe: el.classList.contains('message-out'),
            stamp: pre,
          };
        });
      },
    },
    telegram: {
      source: 'telegram',
      chatTitle() {
        const t =
          document.querySelector('.chat-info .peer-title') ||
          document.querySelector('.top .peer-title') ||
          document.querySelector('.ChatInfo .fullName') ||
          document.querySelector('.MiddleHeader .fullName');
        return t ? textOf(t) : null;
      },
      messages() {
        const k = [...document.querySelectorAll('.bubbles .bubble.is-in, .bubbles .bubble.is-out')].map((el) => {
          const msgEl = el.querySelector('.translatable-message') || el.querySelector('.message');
          let text = '';
          if (msgEl) {
            const c = msgEl.cloneNode(true);
            c.querySelectorAll('.time, .time-inner, .reactions, .bubble-name-forwarded').forEach((n) => n.remove());
            text = textOf(c);
          }
          return { el, anchor: msgEl || el, text, sender: null, fromMe: el.classList.contains('is-out'), stamp: el.dataset.mid || '' };
        });
        if (k.length) return k;
        return [...document.querySelectorAll('.MessageList .Message')].map((el) => {
          const t = el.querySelector('.text-content');
          let text = '';
          if (t) {
            const c = t.cloneNode(true);
            c.querySelectorAll('.MessageMeta, .Reactions').forEach((n) => n.remove());
            text = textOf(c);
          }
          return { el, anchor: t || el, text, sender: null, fromMe: el.classList.contains('own'), stamp: el.id || '' };
        });
      },
    },
  };

  const site = location.host.includes('whatsapp') ? adapters.whatsapp : adapters.telegram;

  // ---- Talking to the Kantoi app (through the background worker) ----------
  const call = (path, body) =>
    new Promise((resolve) => {
      try {
        chrome.runtime.sendMessage({ path, body }, (r) => resolve(r || { ok: false, error: chrome.runtime.lastError?.message }));
      } catch (e) {
        resolve({ ok: false, error: String(e) });
      }
    });

  // ---- Panel --------------------------------------------------------------
  let panel;
  let appUp = false;
  let currentChat = null;
  let lastConversation = null;
  let lastIncomingText = '';
  const origins = {}; // chat -> origin chosen by the user

  function buildPanel() {
    panel = document.createElement('div');
    panel.id = 'kantoi-panel';
    panel.innerHTML = `
      <div class="kantoi-head"><span class="kantoi-dot"></span><b>Kantoi</b><span class="kantoi-toggle">–</span></div>
      <div class="kantoi-body">
        <div class="kantoi-status muted">Connecting to the Kantoi app…</div>
        <div class="kantoi-chat" style="display:none">
          <div class="muted kantoi-chatname"></div>
          <div class="kantoi-score"><span class="n">0</span><span class="kantoi-level"></span></div>
          <div class="kantoi-bar"><div></div></div>
          <div class="kantoi-headline"></div>
          <ul class="kantoi-signals"></ul>
          <label class="muted">How did you first meet them?</label>
          <select class="kantoi-origin">
            <option value="unknown">I'm not sure</option>
            <option value="inPerson">Met in person</option>
            <option value="friendIntro">Introduced by someone I know</option>
            <option value="wrongNumber">They messaged me out of the blue</option>
            <option value="datingApp">Dating app</option>
            <option value="socialMedia">Social media</option>
            <option value="telegramGroup">Telegram or WhatsApp group</option>
          </select>
          <button class="primary kantoi-explain">Explain the latest message</button>
        </div>
      </div>`;
    document.body.appendChild(panel);
    panel.querySelector('.kantoi-head').onclick = () => {
      panel.classList.toggle('kantoi-min');
      panel.querySelector('.kantoi-toggle').textContent = panel.classList.contains('kantoi-min') ? '+' : '–';
    };
    panel.querySelector('.kantoi-origin').onchange = async (e) => {
      if (!currentChat) return;
      origins[currentChat] = e.target.value;
      const r = await call('/conversation', { chat: currentChat, origin: e.target.value, messages: collect() });
      if (r.ok) showConversation(r.data.conversation);
    };
    panel.querySelector('.kantoi-explain').onclick = () => {
      if (lastIncomingText) explain(lastIncomingText);
    };
  }

  function setStatus() {
    const dot = panel.querySelector('.kantoi-dot');
    dot.style.background = appUp ? '#22c55e' : '#ef4444';
    panel.querySelector('.kantoi-status').textContent = appUp
      ? currentChat ? '' : 'Open a chat. Kantoi checks each message you receive.'
      : 'The Kantoi app is not running. Open Kantoi on this computer to turn on protection.';
    panel.querySelector('.kantoi-status').style.display = appUp && currentChat ? 'none' : 'block';
    panel.querySelector('.kantoi-chat').style.display = appUp && currentChat ? 'block' : 'none';
  }

  function showConversation(c) {
    if (!c) return;
    lastConversation = c;
    const color = COLORS[c.level];
    panel.querySelector('.kantoi-chatname').textContent = 'Conversation with ' + currentChat;
    const n = panel.querySelector('.kantoi-score .n');
    n.textContent = c.score;
    n.style.color = color;
    const lv = panel.querySelector('.kantoi-level');
    lv.textContent = LABELS[c.level];
    lv.style.color = color;
    const bar = panel.querySelector('.kantoi-bar > div');
    bar.style.width = c.score + '%';
    bar.style.background = color;
    panel.querySelector('.kantoi-headline').textContent = c.headline;
    const ul = panel.querySelector('.kantoi-signals');
    ul.innerHTML = '';
    [...c.signals].filter((s) => s.weight > 0).sort((a, b) => b.weight - a.weight).slice(0, 4).forEach((s) => {
      const li = document.createElement('li');
      li.textContent = s.title;
      ul.appendChild(li);
    });
    // A clear signal when the conversation crosses into danger.
    if (c.level === 'danger') panel.classList.remove('kantoi-min');
  }

  // ---- Messages -----------------------------------------------------------
  function collect() {
    return site
      .messages()
      .filter((m) => m.text)
      .map((m) => ({ sender: m.fromMe ? 'Me' : m.sender || currentChat, text: m.text, fromMe: m.fromMe, time: stampTime(m.stamp) }));
  }

  // WhatsApp stamps look like "[21:14, 20/10/2026] Ali: " or "[9:14 pm, 20/10/2026] Ali: ".
  // Day-first dates, as used in Malaysia. Returns an ISO string or undefined.
  function stampTime(stamp) {
    const m = (stamp || '').match(/\[(\d{1,2}):(\d{2})\s*([ap]\.?m\.?)?,\s*(\d{1,2})\/(\d{1,2})\/(\d{2,4})\]/i);
    if (!m) return undefined;
    let h = +m[1];
    const ap = (m[3] || '').toLowerCase();
    if (ap.startsWith('p') && h < 12) h += 12;
    if (ap.startsWith('a') && h === 12) h = 0;
    const y = m[6].length === 2 ? 2000 + +m[6] : +m[6];
    const d = new Date(y, +m[5] - 1, +m[4], h, +m[2]);
    return isNaN(d) ? undefined : d.toISOString();
  }

  const keyOf = (m) => (m.stamp || '') + '|' + m.text.slice(0, 200);

  function badge(m, inv) {
    const level = inv.verdict.level;
    m.el.querySelectorAll('.kantoi-badge').forEach((b) => b.remove());
    if (level === 'safe') return;
    const b = document.createElement('div');
    b.className = 'kantoi-badge kantoi-' + level;
    const top = [...new Set(inv.findings.filter((f) => f.weight > 0).sort((a, b) => b.weight - a.weight).map((f) => f.title))].slice(0, 2);
    b.textContent = '⚠ Kantoi: ' + LABELS[level] + (top.length ? ' · ' + top.join(', ') : '') + ' · Why?';
    b.title = inv.verdict.headline + '\n\nNext step: ' + inv.verdict.nextStep;
    b.onclick = (e) => {
      e.stopPropagation();
      explain(m.text);
    };
    (m.anchor.parentElement || m.el).appendChild(b);
  }

  async function explain(text) {
    const r = await call('/explain', { text, chat: currentChat, source: site.source });
    if (!r.ok) alert('Kantoi: open the Kantoi app on this computer to see the full explanation.');
  }

  const checked = new Map(); // key -> verdict json, survives re-renders of the same message
  let busy = false;

  async function scan() {
    if (busy || !appUp) return;
    const title = site.chatTitle();
    if (!title) return;
    busy = true;
    try {
      if (title !== currentChat) {
        currentChat = title;
        setStatus();
        panel.querySelector('.kantoi-origin').value = origins[title] || 'unknown';
        const r = await call('/conversation', { chat: title, origin: origins[title], messages: collect() });
        if (r.ok) showConversation(r.data.conversation);
      }
      const msgs = site.messages().filter((m) => m.text);
      const incoming = msgs.filter((m) => !m.fromMe);
      if (incoming.length) lastIncomingText = incoming[incoming.length - 1].text;
      // Check incoming messages not yet seen; on first open only the latest few.
      const todo = incoming.filter((m) => !checked.has(keyOf(m))).slice(-6);
      for (const m of todo) {
        const r = await call('/check', { chat: title, sender: m.sender || title, text: m.text, fromMe: false, source: site.source });
        if (!r.ok) break;
        checked.set(keyOf(m), r.data.message);
        badge(m, r.data.message);
        showConversation(r.data.conversation);
      }
      // Re-attach badges the chat app removed when it re-rendered.
      for (const m of incoming) {
        const inv = checked.get(keyOf(m));
        if (inv && !m.el.querySelector('.kantoi-badge') && inv.verdict.level !== 'safe') badge(m, inv);
      }
    } finally {
      busy = false;
    }
  }

  let timer;
  const schedule = () => {
    clearTimeout(timer);
    timer = setTimeout(scan, 700);
  };

  async function heartbeat() {
    const r = await call('/health');
    const was = appUp;
    appUp = !!r.ok;
    if (was !== appUp) {
      if (!appUp) currentChat = null;
      setStatus();
      if (appUp) schedule();
    }
  }

  buildPanel();
  setStatus();
  heartbeat();
  setInterval(heartbeat, 8000);
  new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true, characterData: true });
})();
