const TEMPLATE_KEY = 'ofp-template';
const TEMPLATE_DEFS_KEY = 'ofp-template-defs';
const PREFERRED_BROKERS_KEY = 'ofp-preferred-brokers';

const DEFAULT_TEMPLATE_DEFS = [
  {
    key: 'details',
    name: 'Missing Details',
    cc: '',
    subject: '{{avail}} {{origin}} -> {{dest}}{{ref_subject}}',
    body: 'Hi,\nWhat are the details on {{equip_label}}{{ref_body}}?',
  },
  {
    key: 'offer20',
    name: 'Offer +20%',
    cc: '',
    subject: '{{avail}} {{origin}} -> {{dest}}{{ref_subject}}',
    body: [
      'Hi,',
      '{{offer_line}}',
      '',
      'Load details I have:',
      '{{load_details}}',
      '',
      'Please let me know if that works and send the rate confirmation.',
    ].join('\n'),
  },
];

let templateDefs = [];
let selectedKey = 'details';
let preferredBrokerRules = [];
let editingBrokerRuleId = '';

const $ = sel => document.querySelector(sel);

function normalizeTemplateDefs(defs) {
  const arr = Array.isArray(defs) && defs.length ? defs : DEFAULT_TEMPLATE_DEFS;
  return arr.map((def, i) => ({
    key: String(def.key || `template_${Date.now()}_${i}`).trim(),
    name: String(def.name || `Template ${i + 1}`).trim(),
    cc: String(def.cc || '').trim(),
    subject: String(def.subject || DEFAULT_TEMPLATE_DEFS[0].subject),
    body: String(def.body || ''),
  }));
}

function normalizeEmail(raw) {
  if (!raw) return '';
  let s = String(raw).trim().replace(/\s*@\s*/g, '@').replace(/\s+/g, '');
  const at = s.indexOf('@');
  if (at >= 0) s = s.slice(0, at + 1) + s.slice(at + 1).replace(/,/g, '.');
  return s;
}

function isValidEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value);
}

function normalizeMcList(value) {
  const raw = Array.isArray(value) ? value.join(',') : String(value || '');
  return [...new Set([...raw.matchAll(/\d{4,9}/g)].map(m => m[0]))];
}

function normalizePreferredBrokerRules(rules) {
  if (!Array.isArray(rules)) return [];
  return rules.map((rule, i) => ({
    id: String(rule.id || `broker_${Date.now()}_${i}`).trim(),
    company: String(rule.company || '').trim(),
    mcNumbers: normalizeMcList(rule.mcNumbers || rule.mc || rule.mcNumber),
    brokerName: String(rule.brokerName || '').trim(),
    email: normalizeEmail(rule.email || ''),
    notes: String(rule.notes || '').trim(),
    enabled: rule.enabled !== false,
  })).filter(rule => (rule.company || rule.mcNumbers.length) && isValidEmail(rule.email));
}

function chromeGet(keys) {
  return new Promise(resolve => chrome.storage.local.get(keys, resolve));
}

function chromeSet(values) {
  return new Promise(resolve => chrome.storage.local.set(values, resolve));
}

async function activeDatTab() {
  const tabs = await new Promise(resolve => chrome.tabs.query({ active: true, currentWindow: true }, resolve));
  const tab = tabs[0];
  return tab && /^https:\/\/one\.dat\.com\/search-loads/.test(tab.url || '') ? tab : null;
}

async function sendToDat(message) {
  const tab = await activeDatTab();
  if (!tab) return null;
  try {
    return await new Promise(resolve => {
      chrome.tabs.sendMessage(tab.id, message, response => {
        if (chrome.runtime.lastError) resolve(null);
        else resolve(response);
      });
    });
  } catch {
    return null;
  }
}

function selectedTemplate() {
  return templateDefs.find(t => t.key === selectedKey) || templateDefs[0];
}

function renderTemplateList() {
  const list = $('[data-template-list]');
  list.innerHTML = '';
  templateDefs.forEach(template => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = `template-item${template.key === selectedKey ? ' active' : ''}`;
    btn.innerHTML = `<strong>${escapeHtml(template.name)}</strong><span>${escapeHtml(template.subject)}</span>`;
    btn.addEventListener('click', () => {
      selectedKey = template.key;
      render();
    });
    list.appendChild(btn);
  });
}

function renderEditor() {
  const template = selectedTemplate();
  if (!template) return;
  $('[data-name]').value = template.name;
  $('[data-subject]').value = template.subject;
  $('[data-cc]').value = template.cc || '';
  $('[data-body]').value = template.body;
}

function renderDashboard(state = {}) {
  const template = selectedTemplate();
  $('[data-default-template]').textContent = template ? template.name : 'Missing Details';
  $('[data-email-count]').textContent = String(state.emailLogCount ?? 0);
  $('[data-saved-count]').textContent = String(state.savedLoadsCount ?? 0);
  $('[data-email-count-activity]').textContent = String(state.emailLogCount ?? 0);
  $('[data-saved-count-activity]').textContent = String(state.savedLoadsCount ?? 0);
  $('[data-mode]').textContent = state.mode || 'Draft Mode';
  $('[data-status]').textContent = state.connected ? 'DAT Connected' : 'Local';
}

function renderBrokerRules() {
  const list = $('[data-broker-list]');
  if (!list) return;
  list.innerHTML = '';
  $('[data-broker-count]').textContent = `${preferredBrokerRules.length} saved`;

  if (!preferredBrokerRules.length) {
    const empty = document.createElement('div');
    empty.className = 'muted';
    empty.textContent = 'No preferred broker rules yet.';
    list.appendChild(empty);
    return;
  }

  preferredBrokerRules.forEach(rule => {
    const card = document.createElement('div');
    card.className = `broker-rule${rule.enabled ? '' : ' off'}`;
    const label = rule.company || (rule.mcNumbers.length ? `MC ${rule.mcNumbers.join(', MC ')}` : 'Preferred broker');
    card.innerHTML = `
      <strong>${escapeHtml(label)} -> ${escapeHtml(rule.email)}</strong>
      ${rule.mcNumbers.length ? `<span>MC ${escapeHtml(rule.mcNumbers.join(', MC '))}</span>` : ''}
      <span>${escapeHtml(rule.brokerName || 'Preferred broker')} ${rule.enabled ? '' : '(off)'}</span>
      ${rule.notes ? `<span>${escapeHtml(rule.notes)}</span>` : ''}
      <div class="broker-rule-actions">
        <button type="button" data-edit="${escapeHtml(rule.id)}">Edit</button>
        <button type="button" class="secondary" data-toggle="${escapeHtml(rule.id)}">${rule.enabled ? 'Disable' : 'Enable'}</button>
        <button type="button" class="danger" data-delete="${escapeHtml(rule.id)}">Delete</button>
      </div>`;
    list.appendChild(card);
  });
}

function render() {
  renderTemplateList();
  renderEditor();
  renderDashboard();
  renderBrokerRules();
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, ch => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  }[ch]));
}

async function saveAll(statusText = 'Saved') {
  templateDefs = normalizeTemplateDefs(templateDefs);
  await chromeSet({ [TEMPLATE_DEFS_KEY]: templateDefs, [TEMPLATE_KEY]: selectedKey });
  await sendToDat({ type: 'ofp:set-templates', templateDefs, selectedTemplate: selectedKey });
  $('[data-save-status]').textContent = statusText;
  setTimeout(() => { $('[data-save-status]').textContent = ''; }, 1800);
  render();
}

async function savePreferredBrokerRules(statusText = 'Broker rules saved') {
  preferredBrokerRules = normalizePreferredBrokerRules(preferredBrokerRules);
  await chromeSet({ [PREFERRED_BROKERS_KEY]: preferredBrokerRules });
  await sendToDat({ type: 'ofp:set-preferred-brokers', preferredBrokerRules });
  $('[data-broker-status]').textContent = statusText;
  setTimeout(() => { $('[data-broker-status]').textContent = ''; }, 1800);
  renderBrokerRules();
}

function wireTabs() {
  const activate = name => {
    document.querySelectorAll('[data-tab]').forEach(x => x.classList.toggle('active', x.dataset.tab === name));
    document.querySelectorAll('[data-panel]').forEach(panel => {
      panel.classList.toggle('active', panel.dataset.panel === name);
    });
  };

  document.querySelectorAll('[data-tab]').forEach(tab => {
    tab.addEventListener('click', () => activate(tab.dataset.tab));
  });

  document.querySelectorAll('[data-jump-tab]').forEach(tile => {
    tile.addEventListener('click', () => activate(tile.dataset.jumpTab));
  });

  $('[data-open-dat]').addEventListener('click', () => {
    chrome.tabs.create({ url: 'https://one.dat.com/search-loads' });
  });
}

function clearBrokerForm() {
  editingBrokerRuleId = '';
  $('[data-broker-company]').value = '';
  $('[data-broker-mc]').value = '';
  $('[data-broker-name]').value = '';
  $('[data-broker-email]').value = '';
  $('[data-broker-notes]').value = '';
  $('[data-broker-enabled]').checked = true;
}

function wireEditor() {
  $('[data-save-template]').addEventListener('click', async () => {
    const template = selectedTemplate();
    if (!template) return;
    template.name = $('[data-name]').value.trim() || template.name;
    template.subject = $('[data-subject]').value;
    template.cc = $('[data-cc]').value.trim();
    template.body = $('[data-body]').value;
    await saveAll('Template saved');
  });

  $('[data-set-default]').addEventListener('click', async () => {
    await saveAll('Default template set');
  });

  $('[data-add-template]').addEventListener('click', () => {
    const key = `custom_${Date.now()}`;
    templateDefs.push({
      key,
      name: 'New Template',
      cc: '',
      subject: '{{avail}} {{origin}} -> {{dest}}',
      body: 'Hi,\n',
    });
    selectedKey = key;
    render();
    $('[data-name]').focus();
  });

  $('[data-reset-templates]').addEventListener('click', async () => {
    if (!confirm('Reset ONE Freight Pro templates to defaults?')) return;
    templateDefs = normalizeTemplateDefs(DEFAULT_TEMPLATE_DEFS);
    selectedKey = 'details';
    await saveAll('Templates reset');
  });
}

function wireBrokerSettings() {
  $('[data-save-broker-rule]').addEventListener('click', async () => {
    const company = $('[data-broker-company]').value.trim();
    const mcNumbers = normalizeMcList($('[data-broker-mc]').value);
    const brokerName = $('[data-broker-name]').value.trim();
    const email = normalizeEmail($('[data-broker-email]').value);
    const notes = $('[data-broker-notes]').value.trim();
    const enabled = $('[data-broker-enabled]').checked;

    if (!company && !mcNumbers.length) {
      $('[data-broker-status]').textContent = 'Add an MC number or brokerage/company match.';
      return;
    }
    if (!isValidEmail(email)) {
      $('[data-broker-status]').textContent = 'Add a valid preferred email.';
      return;
    }

    const rule = {
      id: editingBrokerRuleId || (mcNumbers[0] ? `broker_mc_${mcNumbers[0]}_${Date.now()}` : `broker_${Date.now()}`),
      company,
      mcNumbers,
      brokerName,
      email,
      notes,
      enabled,
    };
    const idx = preferredBrokerRules.findIndex(x => x.id === rule.id);
    if (idx >= 0) preferredBrokerRules[idx] = rule;
    else preferredBrokerRules.push(rule);
    clearBrokerForm();
    await savePreferredBrokerRules('Preferred broker saved');
  });

  $('[data-clear-broker-form]').addEventListener('click', e => {
    e.preventDefault();
    clearBrokerForm();
  });

  $('[data-broker-list]').addEventListener('click', async e => {
    const editId = e.target.dataset.edit;
    const toggleId = e.target.dataset.toggle;
    const deleteId = e.target.dataset.delete;

    if (editId) {
      const rule = preferredBrokerRules.find(x => x.id === editId);
      if (!rule) return;
      editingBrokerRuleId = rule.id;
      $('[data-broker-company]').value = rule.company;
      $('[data-broker-mc]').value = (rule.mcNumbers || []).join(', ');
      $('[data-broker-name]').value = rule.brokerName;
      $('[data-broker-email]').value = rule.email;
      $('[data-broker-notes]').value = rule.notes;
      $('[data-broker-enabled]').checked = rule.enabled;
      return;
    }

    if (toggleId) {
      const rule = preferredBrokerRules.find(x => x.id === toggleId);
      if (!rule) return;
      rule.enabled = !rule.enabled;
      await savePreferredBrokerRules(rule.enabled ? 'Rule enabled' : 'Rule disabled');
      return;
    }

    if (deleteId) {
      preferredBrokerRules = preferredBrokerRules.filter(x => x.id !== deleteId);
      if (editingBrokerRuleId === deleteId) clearBrokerForm();
      await savePreferredBrokerRules('Rule deleted');
    }
  });
}

async function init() {
  wireTabs();
  wireEditor();
  wireBrokerSettings();

  const stored = await chromeGet([TEMPLATE_DEFS_KEY, TEMPLATE_KEY, PREFERRED_BROKERS_KEY]);
  templateDefs = normalizeTemplateDefs(stored[TEMPLATE_DEFS_KEY]);
  selectedKey = stored[TEMPLATE_KEY] || templateDefs[0].key;
  preferredBrokerRules = normalizePreferredBrokerRules(stored[PREFERRED_BROKERS_KEY]);

  const state = await sendToDat({ type: 'ofp:get-state' });
  if (state && state.ok) {
    templateDefs = normalizeTemplateDefs(state.templateDefs || templateDefs);
    preferredBrokerRules = normalizePreferredBrokerRules(state.preferredBrokerRules || preferredBrokerRules);
    selectedKey = state.selectedTemplate || selectedKey;
    await chromeSet({
      [TEMPLATE_DEFS_KEY]: templateDefs,
      [TEMPLATE_KEY]: selectedKey,
      [PREFERRED_BROKERS_KEY]: preferredBrokerRules,
    });
    render();
    renderDashboard({ ...state, connected: true });
  } else {
    render();
  }
}

init();
