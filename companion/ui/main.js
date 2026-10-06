// The status window: shows what the companion's background thread found.
// Everything is set with textContent, never as HTML.

const { invoke } = window.__TAURI__.core
const { listen } = window.__TAURI__.event

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag)
  for (const [k, v] of Object.entries(attrs)) node[k] = v
  for (const c of children) node.append(c)
  return node
}

function ago(unix) {
  if (!unix) return ''
  const s = Math.max(0, Math.round(Date.now() / 1000 - unix))
  if (s < 60) return 'just now'
  if (s < 3600) return `${Math.round(s / 60)} min ago`
  if (s < 86400) return `${Math.round(s / 3600)} h ago`
  return `${Math.round(s / 86400)} days ago`
}

function account(a) {
  let line
  if (a.state === 'missing') line = el('span', { className: 'muted', textContent: 'No Soapstone data yet (log in with the addon enabled)' })
  else if (a.state === 'settling') line = el('span', { className: 'muted', textContent: 'WoW is saving…' })
  else if (a.state === 'unreadable') line = el('span', { className: 'warn', textContent: `Can't read Soapstone.lua: ${a.error}` })
  else {
    const s = a.summary
    const chars = s.meta && s.meta.characters.length ? ` · ${s.meta.characters.map((c) => c.replace('-', ' ')).join(', ')}` : ''
    const game = s.meta ? `${s.meta.flavor ?? '?'} · ${(s.meta.region ?? 'region unknown').toUpperCase()}${chars}` : 'game type not recorded yet (needs addon 0.5)'
    const waiting = s.waiting === 1 ? '1 change waiting' : `${s.waiting} changes waiting`
    line = el('span', {}, `${s.stones} stones · ${waiting} · `, el('span', { className: 'muted', textContent: game }))
  }
  return el('li', {},
    el('div', { className: 'row' }, el('strong', { textContent: a.name }), el('span', { className: 'muted small', textContent: a.summary ? `saved ${ago(a.summary.modified)}` : '' })),
    line)
}

function folder(f) {
  const addon = !f.addon
    ? el('span', { className: 'warn', textContent: 'Addon not installed' })
    : el('span', { className: 'muted', textContent: f.addon.linked ? 'Addon linked (developer copy, never overwritten)' : 'Addon installed' })
  const accounts = f.accounts.length
    ? el('ul', {}, ...f.accounts.map(account))
    : el('p', { className: 'muted', textContent: 'No accounts yet. Log in once to create one.' })
  return el('section', { className: 'card' },
    el('div', { className: 'row' }, el('h2', { textContent: f.name }), addon),
    el('div', { className: 'path', textContent: f.path }),
    accounts)
}

function render(s) {
  document.getElementById('server').textContent = s.server
  const conn = document.getElementById('connection')
  conn.textContent = s.connection || 'Connecting…'
  conn.className = s.connected ? 'ok' : 'warn'
  document.getElementById('scanned').textContent = s.scannedAt ? `checked ${ago(s.scannedAt)}` : ''
  document.getElementById('config').textContent = s.configPath ?? ''
  const folders = document.getElementById('folders')
  folders.replaceChildren(...(s.folders.length
    ? s.folders.map(folder)
    : [el('section', { className: 'card' }, el('p', { textContent: 'No WoW folders found yet.' }))]))
}

let last = null
listen('status', (e) => { last = e.payload; render(last) })
invoke('status').then((s) => { last = s; render(s) })
setInterval(() => last && render(last), 30_000) // keep "x min ago" fresh
document.getElementById('rescan').addEventListener('click', () => invoke('rescan'))
