const GMAIL_ACCOUNT_KEY = 'ofp-gmail-account';
const GMAIL_API_BASE = 'https://gmail.googleapis.com/gmail/v1/users/me';
const OAUTH_PLACEHOLDER = 'REPLACE_WITH_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com';

function getManifestClientId() {
  return (chrome.runtime.getManifest().oauth2 || {}).client_id || '';
}

function isOAuthConfigured() {
  const clientId = getManifestClientId();
  return clientId && clientId !== OAUTH_PLACEHOLDER && !/^REPLACE_/i.test(clientId);
}

function chromeStorageSet(values) {
  return new Promise(resolve => chrome.storage.local.set(values, resolve));
}

function getAuthToken(interactive = true) {
  return new Promise((resolve, reject) => {
    if (!isOAuthConfigured()) {
      reject(new Error('Gmail OAuth client ID is not configured yet.'));
      return;
    }
    chrome.identity.getAuthToken({ interactive }, token => {
      if (chrome.runtime.lastError || !token) {
        reject(new Error((chrome.runtime.lastError && chrome.runtime.lastError.message) || 'Gmail authorization failed.'));
        return;
      }
      resolve(token);
    });
  });
}

function removeCachedToken(token) {
  return new Promise(resolve => {
    if (!token) {
      resolve();
      return;
    }
    chrome.identity.removeCachedAuthToken({ token }, resolve);
  });
}

async function gmailFetch(path, options = {}) {
  const token = await getAuthToken(options.interactive !== false);
  const response = await fetch(`${GMAIL_API_BASE}${path}`, {
    method: options.method || 'GET',
    headers: Object.assign({
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    }, options.headers || {}),
    body: options.body ? JSON.stringify(options.body) : undefined,
  });

  if (response.status === 401) {
    await removeCachedToken(token);
  }

  if (!response.ok) {
    let detail = '';
    try { detail = (await response.json()).error?.message || ''; } catch {}
    throw new Error(detail || `Gmail API request failed (${response.status}).`);
  }

  return response.status === 204 ? {} : response.json();
}

function encodeHeader(value) {
  const text = String(value || '');
  return /^[\x00-\x7F]*$/.test(text)
    ? text
    : `=?UTF-8?B?${base64Encode(text)}?=`;
}

function base64Encode(text) {
  const bytes = new TextEncoder().encode(String(text || ''));
  let binary = '';
  bytes.forEach(byte => { binary += String.fromCharCode(byte); });
  return btoa(binary);
}

function base64UrlEncode(text) {
  return base64Encode(text).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function buildRawEmail(payload) {
  const lines = [
    `To: ${payload.to || ''}`,
    `Subject: ${encodeHeader(payload.subject || '')}`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset="UTF-8"',
    'Content-Transfer-Encoding: 8bit',
    '',
    payload.body || '',
  ];
  if (payload.cc) lines.splice(1, 0, `Cc: ${payload.cc}`);
  return base64UrlEncode(lines.join('\r\n'));
}

async function connectGmail() {
  const profile = await gmailFetch('/profile', { interactive: true });
  await chromeStorageSet({ [GMAIL_ACCOUNT_KEY]: profile.emailAddress || '' });
  return { ok: true, emailAddress: profile.emailAddress || '' };
}

async function deliverGmail(payload) {
  if (!payload || !payload.to) throw new Error('Missing recipient email.');
  const raw = buildRawEmail(payload);
  if (payload.mode === 'send') {
    const sent = await gmailFetch('/messages/send', { method: 'POST', body: { raw } });
    return { ok: true, mode: 'send', id: sent.id || '' };
  }
  const draft = await gmailFetch('/drafts', { method: 'POST', body: { message: { raw } } });
  return { ok: true, mode: 'draft', id: draft.id || '' };
}

async function disconnectGmail() {
  try {
    const token = await getAuthToken(false);
    await removeCachedToken(token);
  } catch {}
  await chromeStorageSet({ [GMAIL_ACCOUNT_KEY]: '' });
  return { ok: true };
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || !message.type) return false;

  const run = async () => {
    if (message.type === 'ofp:gmail-connect') return connectGmail();
    if (message.type === 'ofp:gmail-disconnect') return disconnectGmail();
    if (message.type === 'ofp:gmail-deliver') return deliverGmail(message.payload);
    return { ok: false, error: 'Unknown ONE Freight Pro Gmail command.' };
  };

  run()
    .then(result => sendResponse(result))
    .catch(error => sendResponse({ ok: false, error: error.message || String(error) }));
  return true;
});
