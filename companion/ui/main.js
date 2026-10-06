// The status window: shows what the companion's background thread found.
// Everything is set with textContent, never as HTML.
//
// Plain words up front (is everything shared? what should I do?), and the
// technical facts (folders, codes, ids, raw errors) in collapsed
// "Details for troubleshooting" sections.

const { invoke } = window.__TAURI__.core
const { listen } = window.__TAURI__.event

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag)
  for (const [k, v] of Object.entries(attrs)) node[k] = v
  for (const c of children) if (c !== null && c !== undefined && c !== '') node.append(c)
  return node
}

function ago(unix) {
  if (!unix) return 'never'
  const s = Math.max(0, Math.round(Date.now() / 1000 - unix))
  if (s < 60) return 'just now'
  if (s < 3600) return `${Math.round(s / 60)} min ago`
  if (s < 86400) return `${Math.round(s / 3600)} h ago`
  return `${Math.round(s / 86400)} days ago`
}

function clock(unix) {
  return unix ? new Date(unix * 1000).toLocaleString() : '—'
}

const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`

// "forever" + "test" -> "WoW Forever beta"; "retail" + "eu" -> "World of Warcraft · EU"
const GAMES = { forever: 'WoW Forever', retail: 'World of Warcraft', classic: 'WoW Classic' }
function gameName(flavor, region) {
  let name = GAMES[flavor] || (flavor && flavor.startsWith('classic-') ? 'WoW Classic' : 'World of Warcraft')
  if (region === 'test') return `${name} beta`
  if (region) return `${name} · ${region.toUpperCase()}`
  return name
}

// "Mad-Decent" -> "Mad Decent" on WoW Forever (first and last name); elsewhere
// the second part is a realm: "Mad-Stormrage" -> "Mad of Stormrage".
function characterName(key, flavor) {
  const [name, rest] = key.split(/-(.*)/)
  if (!rest) return name
  return flavor === 'forever' ? `${name} ${rest}` : `${name} of ${rest}`
}

function fact(list, label, value, code = false) {
  list.push(el('dt', { textContent: label }), el('dd', { className: code ? 'code' : '', textContent: value ?? '—' }))
}

// One account (usually the only one in a game folder).
function accountRows(a, label) {
  const rows = []
  const row = (name, ...value) => rows.push(el('dt', { textContent: name }), el('dd', {}, ...value))
  const s = a.summary
  if (a.state === 'missing') {
    row('Sharing', 'No Soapstone data yet. Log in to a character with the addon enabled.')
  } else if (a.state === 'settling') {
    row('Sharing', 'WoW is saving…')
  } else if (a.state === 'unreadable') {
    row('Sharing', el('span', { className: 'warn', textContent: "Soapstone's saved data couldn't be read. See the details below." }))
  } else {
    row('Stones', `${s.stones} on your maps`)
    const flavor = s.meta && s.meta.flavor
    const chars = s.meta ? s.meta.characters : []
    row('Characters', chars.length
      ? el('span', { className: 'chips' }, ...chars.map((c) => el('span', { className: 'chip', textContent: characterName(c, flavor) })))
      : el('span', { className: 'muted', textContent: 'Log in once with the latest addon to add your characters' }))
    let sharing
    if (!s.meta) sharing = el('span', { className: 'warn', textContent: 'Update the Soapstone addon and log in once, so the companion knows which game this is.' })
    else if (s.waiting > 0) sharing = el('span', {}, `${plural(s.waiting, 'change', 'changes')} waiting to upload`)
    else sharing = el('span', { className: 'ok', textContent: 'All your changes are uploaded' })
    row('Sharing', sharing, s.confirmed
      ? el('div', { className: 'muted small', textContent: `${plural(s.confirmed, 'change was', 'changes were')} just uploaded. WoW confirms ${s.confirmed === 1 ? 'it' : 'them'} at your next /reload or logout.` })
      : null)
  }
  const block = []
  if (label) block.push(el('h3', { textContent: label }))
  block.push(el('dl', {}, ...rows))
  return block
}

// Which troubleshooting sections are open, so a refresh doesn't close them.
const openDetails = new Set()
function remember(key, open) {
  if (open) openDetails.add(key)
  else openDetails.delete(key)
}

function gameCard(f) {
  const withMeta = f.accounts.find((a) => a.summary && a.summary.meta)
  const meta = withMeta && withMeta.summary.meta
  const title = meta ? gameName(meta.flavor, meta.region) : `World of Warcraft (${f.name})`
  const badge = !f.addon
    ? el('span', { className: 'badge warn', textContent: 'Addon not installed' })
    : el('span', { className: 'badge', textContent: f.addon.linked ? 'Addon linked (developer copy)' : 'Addon installed' })

  const body = []
  const many = f.accounts.length > 1
  f.accounts.forEach((a, i) => body.push(...accountRows(a, many ? `WoW account ${i + 1}` : null)))
  if (!f.accounts.length) body.push(el('p', { className: 'muted', textContent: 'No characters yet. Log in once with the Soapstone addon enabled.' }))

  const sync = f.sync || {}
  const r = sync.report
  const lastSync = []
  if (r && r.error) lastSync.push(el('span', { className: 'warn', textContent: "Couldn't finish. It'll try again shortly." }))
  if (sync.syncedAt) {
    const parts = [ago(sync.syncedAt)]
    if (r && !r.error) {
      if (r.uploaded) parts.push(`sent ${r.uploaded}`)
      if (r.downloaded) parts.push(`received ${r.downloaded}`)
      if (r.removed) parts.push(`${r.removed} removed`)
      if (r.refused) parts.push(`${r.refused} not accepted`)
    }
    lastSync.push(el('div', { textContent: (r && r.error ? 'Last finished ' : '') + parts.join(' · ') }))
  } else if (!(r && r.error)) lastSync.push(el('span', { className: 'muted', textContent: 'Not yet' }))
  body.push(el('dl', {}, el('dt', { textContent: 'Last sync' }), el('dd', {}, ...lastSync)))

  if (sync.addon) body.push(el('div', { className: 'note', textContent: sync.addon }))
  if (sync.installed) body.push(el('div', { className: 'note', textContent: 'Soapstone just added its data to your game. Restart WoW once so it can load it; after that a /reload is enough.' }))
  if (sync.note) body.push(el('div', { className: 'note', textContent: sync.note }))

  // Troubleshooting.
  const facts = []
  fact(facts, 'Game folder', f.path, true)
  if (meta) fact(facts, 'Game code', `${meta.flavor} · region ${meta.region ?? 'unknown'}`, true)
  if (f.addon) fact(facts, 'Addon folder', f.addon.path, true)
  if (sync.addonManaged) fact(facts, 'Kept up to date by the companion', sync.addonManaged)
  if (f.build) fact(facts, 'Game version', f.build)
  f.accounts.forEach((a, i) => {
    const label = (name) => (many ? `Account ${i + 1} · ${name.toLowerCase()}` : name)
    fact(facts, label('Account folder'), a.name, true)
    fact(facts, label('Saved data'), a.savedVariables, true)
    if (a.summary) {
      fact(facts, label('Last saved'), `${clock(a.summary.modified)} (${ago(a.summary.modified)})`)
      fact(facts, label('In the file'), `${a.summary.waiting + a.summary.confirmed} pending · ${a.summary.confirmed} already answered by the server`)
      if (a.summary.meta) fact(facts, label('Addon version'), a.summary.meta.addon)
    }
    if (a.error) fact(facts, label('Read error'), a.error, true)
  })
  if (r) fact(facts, 'Last sync result', `sent ${r.uploaded}, not accepted ${r.refused}, received ${r.downloaded}, removed ${r.removed}`)
  if (r && r.error) fact(facts, 'Sync error', r.error, true)

  return el('section', { className: 'card' },
    el('div', { className: 'head' }, el('h2', { textContent: title }), badge),
    ...body,
    el('details', { open: openDetails.has(f.path), ontoggle: (e) => remember(f.path, e.target.open) },
      el('summary', { textContent: 'Details for troubleshooting' }), el('dl', { className: 'facts' }, ...facts)))
}

function render(s) {
  const accounts = s.folders.flatMap((f) => f.accounts).filter((a) => a.summary)
  const waiting = accounts.reduce((n, a) => n + a.summary.waiting, 0)
  let dot = 'ok', headline, subline
  if (!s.folders.length) {
    dot = 'warn'
    headline = "Couldn't find World of Warcraft"
    subline = 'Soapstone looks in the usual places on every drive.'
  } else if (!s.connected) {
    dot = 'warn'
    headline = "Can't reach the Soapstone server"
    subline = "Your stones are safe in the game. They'll upload as soon as the connection is back."
  } else if (waiting > 0) {
    dot = ''
    headline = `${plural(waiting, 'change', 'changes')} waiting to upload`
    subline = "They'll go up within a minute."
  } else {
    headline = "Everything's shared"
    subline = `Your drops, appraisals and finds are on the server. Checked ${ago(s.scannedAt)}.`
  }
  document.getElementById('dot').className = `dot ${dot}`
  document.getElementById('headline').textContent = headline
  document.getElementById('subline').textContent = subline

  document.getElementById('games').replaceChildren(...s.folders.map(gameCard))

  const facts = []
  fact(facts, 'Server', s.server, true)
  fact(facts, 'Connection', s.connectionDetail)
  fact(facts, 'Install id', s.installId, true)
  fact(facts, 'Settings file', s.configPath, true)
  fact(facts, 'Last checked', `${clock(s.scannedAt)} (${ago(s.scannedAt)})`)
  document.getElementById('facts').replaceChildren(...facts)

  const button = document.getElementById('rescan')
  button.disabled = false
  button.textContent = 'Check now'
}

let last = null
listen('status', (e) => { last = e.payload; render(last) })
invoke('status').then((s) => { if (s.scannedAt) { last = s; render(s) } })
setInterval(() => last && render(last), 30_000) // keep "x min ago" fresh
document.getElementById('rescan').addEventListener('click', (e) => {
  e.target.disabled = true
  e.target.textContent = 'Checking…'
  invoke('rescan')
})
