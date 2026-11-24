/* UNP_GUI front-end (vanilla JS, no dependencies) */
'use strict';
const $ = s => document.querySelector(s);
const $$ = s => Array.from(document.querySelectorAll(s));
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

const S = {            // app state
  state: null,        // /api/state
  project: localStorage.getItem('unp.project') || '',
  overview: null,     // /api/project
  pairs: [],          // selected {subject, session, sid,...}
  jobs: [], queue: [],
  qcRows: [], qcSort: {k: 'sid', dir: 1},
  drawerSid: null, drawerData: null,
  timer: null,
};

// ---------------------------------------------------------------- helpers
async function api(path, body) {
  const opt = body ? {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)} : {};
  const r = await fetch('/api/' + path, opt);
  let j; try { j = await r.json(); } catch (e) { j = {error: 'bad response'}; }
  if (!r.ok || j.error) throw new Error(j.error || r.statusText);
  return j;
}
function toast(msg, err) {
  const t = $('#toast'); t.textContent = msg; t.className = err ? 'err' : ''; t.classList.remove('hidden');
  clearTimeout(t._t); t._t = setTimeout(() => t.classList.add('hidden'), err ? 8000 : 3500);
}
function modal(title, html) { $('#modal-title').textContent = title; $('#modal-body').innerHTML = html; $('#modal').classList.remove('hidden'); }
$('#modal-close').onclick = () => $('#modal').classList.add('hidden');
$('#modal').addEventListener('click', e => { if (e.target.id === 'modal') $('#modal').classList.add('hidden'); });
function showTab(name) {
  $$('#tabs button').forEach(b => b.classList.toggle('active', b.dataset.tab === name));
  $$('.tab').forEach(t => t.classList.toggle('active', t.id === 'tab-' + name));
  localStorage.setItem('unp.tab', name);
  if (name === 'status') loadProject();
  if (name === 'jobs') loadJobs();
  if (name === 'qc') loadQC();
  if (name === 'pfm') loadTM();
  if (name === 'study') loadStudy();
  if (name === 'settings') fillSettings();
}
$$('#tabs button').forEach(b => b.onclick = () => showTab(b.dataset.tab));
document.addEventListener('keydown', e => { if (e.key === 'Escape') { closeDrawer(); $('#modal').classList.add('hidden'); } });
function fileUrl(p, dl) { return '/api/file?path=' + encodeURIComponent(p) + (dl ? '&dl=1' : ''); }
function pill(state) { return `<span class="pill ${esc(state)}">${esc(state)}</span>`; }
function csvDownload(name, rows) {
  const csv = rows.map(r => r.map(v => `"${String(v ?? '').replace(/"/g, '""')}"`).join(',')).join('\n');
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([csv], {type: 'text/csv'})); a.download = name; a.click();
}

// ---------------------------------------------------------------- boot
async function boot() {
  try { S.state = await api('state'); } catch (e) { toast('Cannot reach server: ' + e.message, true); return; }
  const st = S.state;
  $('#whoami').textContent = `${st.user}@${st.host}`;
  $('#exec-host').textContent = st.host;
  $$('input[name=executor]').forEach(r => r.onchange = () => {
    const loc = document.querySelector('input[name=executor]:checked').value === 'local';
    $('#local-opts').classList.toggle('hidden', !loc);
    $$('#tab-run .grid2 input, #tab-run .grid2 select').forEach(el => el.disabled = loc && !['s-notify', 's-notify-on'].includes(el.id));
  });
  $('#fake-badge').classList.toggle('hidden', !st.fake_slurm);
  $('#ssh-badge').classList.toggle('hidden', st.ssh_master !== false);
  // project selector: union of Scans projects and Projects
  const names = Array.from(new Set([...st.projects, ...st.scan_projects])).sort();
  const sel = $('#project');
  sel.innerHTML = '<option value="">— select —</option>' + names.map(n => {
    const inS = st.scan_projects.includes(n), inP = st.projects.includes(n);
    return `<option value="${esc(n)}">${esc(n)}${!inP ? ' (Scans only – not configured)' : (!inS ? ' (no Scans folder)' : '')}</option>`;
  }).join('');
  if (names.includes(S.project)) sel.value = S.project; else S.project = '';
  sel.onchange = () => { S.project = sel.value; localStorage.setItem('unp.project', S.project); S.pairs = []; renderPairs(); S.overview = null; refreshAll(); };
  buildModules(); buildSlurmForm();
  showTab(localStorage.getItem('unp.tab') || 'run');
  refreshAll();
  const period = Math.max(10, st.config.refresh_seconds || 30) * 1000;
  S.timer = setInterval(() => {
    const tab = localStorage.getItem('unp.tab');
    if (tab === 'status') loadProject(true);
    if (tab === 'jobs') loadJobs(true);
    if (S.drawerSid && !$('#drawer').classList.contains('hidden')) openSubject(S.drawerSid, true);
  }, period);
}
$('#btn-refresh').onclick = refreshAll;
function refreshAll() { const tab = localStorage.getItem('unp.tab') || 'run'; showTab(tab); if (tab === 'run') loadProject(); }

// ---------------------------------------------------------------- RUN: modules / overrides / slurm form
function buildModules() {
  const box = $('#modules'); box.innerHTML = '';
  let section = '';
  for (const m of S.state.modules) {
    if (m.section !== section) { section = m.section; box.insertAdjacentHTML('beforeend', `<div class="mod-section">${esc(section)}</div>`); }
    box.insertAdjacentHTML('beforeend',
      `<label class="mod"><input type="checkbox" class="modchk" value="${esc(m.flag)}"><code>${esc(m.flag)}</code><span class="desc" title="${esc(m.desc)}\n${esc(m.script)}">${esc(m.desc)}</span></label>`);
  }
  setModules(S.state.config.default_steps || ['-reg', '-fMRI', '-surf', '-QC']);
  $('#preset-standard').onclick = () => setModules(['-reg', '-fMRI', '-surf', '-QC']);
  $('#preset-reg').onclick = () => setModules(['-BOLD', '-fMRI', '-surf', '-QC']);
  $('#preset-none').onclick = () => setModules([]);
  $('#btn-add-override').onclick = () => addOverride();
}
function setModules(list) { $$('.modchk').forEach(c => c.checked = list.includes(c.value)); }
function selectedModules() { return $$('.modchk').filter(c => c.checked).map(c => c.value); }
function addOverride(flag, value) {
  const opts = S.state.overrides.map(o => `<option value="${esc(o.flag)}" ${o.flag === flag ? 'selected' : ''}>${esc(o.flag)}</option>`).join('');
  const div = document.createElement('div'); div.className = 'override';
  div.innerHTML = `<select class="ov-flag">${opts}</select><input class="ov-val" placeholder="value" value="${esc(value ?? '')}"><span class="desc muted"></span><button class="ghost small">✕</button>`;
  const upd = () => { const o = S.state.overrides.find(x => x.flag === div.querySelector('.ov-flag').value);
    div.querySelector('.ov-val').style.display = o && o.takes_value ? '' : 'none'; div.querySelector('.desc').textContent = o ? o.desc : ''; };
  div.querySelector('.ov-flag').onchange = upd; upd();
  div.querySelector('button').onclick = () => div.remove();
  $('#overrides').appendChild(div);
}
function selectedOverrides() {
  return $$('.override').map(d => ({flag: d.querySelector('.ov-flag').value, value: d.querySelector('.ov-val').value}));
}
function buildSlurmForm() {
  const c = S.state.config.slurm;
  const parts = S.state.partitions.map(p => `<option value="${esc(p.name)}">${esc(p.name)}${p.time ? ' (' + esc(p.time) + ')' : ''}</option>`).join('');
  for (const id of ['#s-partition', '#s-ppartition']) {
    const sel = $(id); sel.innerHTML = parts;
    const want = id === '#s-partition' ? c.partition : c.propagate_partition;
    if (![...sel.options].some(o => o.value === want)) sel.insertAdjacentHTML('afterbegin', `<option value="${esc(want)}">${esc(want)}</option>`);
    sel.value = want;
  }
  $('#s-cpus').value = c.cpus_per_task; $('#s-mem').value = c.mem; $('#s-time').value = c.time;
  $('#s-account').value = c.account || ''; $('#s-mail').value = c.mail_user || ''; $('#s-mailtype').value = c.mail_type || '';
  $('#s-notify').value = S.state.config.notify_email || ''; $('#s-notify-on').value = S.state.config.notify_on || 'always';
  $('#partitions-info').textContent = 'Partitions (sinfo):\n' + S.state.partitions.map(p => `  ${p.name.padEnd(16)} ${p.avail || ''}  max ${p.time || '?'}`).join('\n');
}
function slurmOpts() {
  return {partition: $('#s-partition').value, cpus_per_task: +$('#s-cpus').value, mem: $('#s-mem').value, time: $('#s-time').value,
    account: $('#s-account').value, mail_user: $('#s-mail').value, mail_type: $('#s-mailtype').value, propagate_partition: $('#s-ppartition').value};
}

// ---------------------------------------------------------------- RUN: subjects
$('#btn-parse').onclick = parseList;
$('#listfile').onchange = e => { const f = e.target.files[0]; if (!f) return; f.text().then(t => { $('#sublist').value = t; parseList(); }); e.target.value = ''; };
$('#btn-clear-sel').onclick = () => { S.pairs = []; $('#sublist').value = ''; renderPairs(); };
$('#btn-pick').onclick = togglePicker;
async function parseList() {
  if (!S.project) return toast('Select a project first', true);
  try {
    const r = await api('parse_list', {project: S.project, text: $('#sublist').value});
    for (const p of r.pairs) if (!S.pairs.some(x => x.sid === p.sid)) S.pairs.push(p);
    renderPairs();
  } catch (e) { toast(e.message, true); }
}
function day1Select(p, cls) {
  const cands = p.day1_candidates || [];
  if (!p.day1_init) { p.day1_init = true; if (!p.day1 && p.day1_suggested) p.day1 = p.day1_suggested; }
  const opts = ['<option value="">this session is day 1</option>'].concat(cands.map(c =>
    `<option value="${esc(c.sid)}" ${c.sid === p.day1 ? 'selected' : ''}>${esc(c.sid)}${c.has_t1 ? '' : (c.in_batch ? ' (in this batch)' : ' (no T1 yet!)')}${c.day1 ? ' (itself day 2+)' : ''}</option>`));
  if (p.day1 && !cands.some(c => c.sid === p.day1)) opts.push(`<option value="${esc(p.day1)}" selected>${esc(p.day1)} (from params)</option>`);
  return `<select class="${cls}" data-sid="${esc(p.sid)}" ${cands.length || p.day1 ? '' : 'disabled'} title="day1_path">${opts.join('')}</select>` +
    (p.day1_suggested && p.day1 === p.day1_suggested ? ' <span class="muted" title="earliest other session of this subject with a registered T1">suggested</span>' : '');
}
function renderPairs() {
  const tb = $('#pairs tbody'); tb.innerHTML = '';
  S.pairs.forEach((p, i) => {
    tb.insertAdjacentHTML('beforeend', `<tr>
      <td><button class="ghost small" data-i="${i}">✕</button></td><td>${esc(p.subject)}</td><td>${esc(p.session ?? '')}</td>
      <td><code>${esc(p.sid)}</code></td><td>${p.in_scans ? '✓' : '<span class="err">–</span>'}</td>
      <td>${p.propagated ? '✓' : '–'}</td><td>${day1Select(p, 'day1-sel')}</td><td class="muted">${esc(p.warning || '')}</td></tr>`);
  });
  tb.querySelectorAll('button').forEach(b => b.onclick = () => { S.pairs.splice(+b.dataset.i, 1); renderPairs(); });
  tb.querySelectorAll('select.day1-sel').forEach(sel => sel.onchange = () => { const p = S.pairs.find(x => x.sid === sel.dataset.sid); if (p) { p.day1 = sel.value; p.day1_suggested = ''; renderPairs(); } });
  const n = S.pairs.length, np = S.pairs.filter(p => !p.propagated).length;
  $('#pairs-summary').textContent = n ? `${n} subject-session(s) selected, ${np} not yet propagated` : 'nothing selected';
  if (np && n) $('#do-propagate').checked = $('#do-propagate').checked || np === n;
}
async function togglePicker() {
  const box = $('#scan-picker');
  if (!box.classList.contains('hidden')) { box.classList.add('hidden'); return; }
  if (!S.project) return toast('Select a project first', true);
  const scans = await api('scans?project=' + encodeURIComponent(S.project));
  const inproc = new Set((S.overview?.rows || []).filter(r => r.propagated).map(r => r.id));
  let html = `<div class="row" style="columns:auto"><button class="ghost small" id="pk-all">select all</button><button class="ghost small" id="pk-none">none</button>
     <button class="ghost small" id="pk-new">only not-propagated</button><button class="primary small" id="pk-add">Add selected</button></div>`;
  for (const [sub, sess] of Object.entries(scans)) {
    html += `<div class="sub"><b data-sub="${esc(sub)}">${esc(sub)}</b>` +
      sess.map(s => { const sid = `${sub}_${s}`; return `<label class="ses"><input type="checkbox" data-sub="${esc(sub)}" data-ses="${esc(s)}"> ${esc(s)} ${inproc.has(sid) ? '<span class="muted">(propagated)</span>' : ''}</label>`; }).join('') + `</div>`;
  }
  if (!Object.keys(scans).length) html += `<p class="muted">No subject folders found in Scans/${esc(S.project)}.</p>`;
  box.innerHTML = html; box.classList.remove('hidden');
  const cbs = () => Array.from(box.querySelectorAll('input[type=checkbox]'));
  box.querySelectorAll('b[data-sub]').forEach(b => b.onclick = () => { const c = cbs().filter(x => x.dataset.sub === b.dataset.sub); const v = !c.every(x => x.checked); c.forEach(x => x.checked = v); });
  $('#pk-all').onclick = () => cbs().forEach(c => c.checked = true);
  $('#pk-none').onclick = () => cbs().forEach(c => c.checked = false);
  $('#pk-new').onclick = () => cbs().forEach(c => c.checked = !inproc.has(`${c.dataset.sub}_${c.dataset.ses}`));
  $('#pk-add').onclick = () => {
    const lines = cbs().filter(c => c.checked).map(c => `${c.dataset.sub} ${c.dataset.ses}`);
    $('#sublist').value = ($('#sublist').value.trim() + '\n' + lines.join('\n')).trim(); parseList(); box.classList.add('hidden');
  };
}

// ---------------------------------------------------------------- RUN: submit
function submitBody(dry) {
  return {project: S.project, pairs: S.pairs.map(p => ({subject: p.subject, session: p.session, day1: p.day1 || ''})),
    steps: selectedModules(), overrides: selectedOverrides(), propagate: $('#do-propagate').checked,
    propagate_opts: {force: $('#prop-force').checked, no_init: $('#prop-noinit').checked},
    executor: document.querySelector('input[name=executor]:checked').value, local_serial: $('#local-serial').checked,
    slurm: slurmOpts(), notify_email: $('#s-notify').value, notify_on: $('#s-notify-on').value,
    clear_locks: $('#clear-locks').checked, force: $('#force-submit').checked, dry_run: !!dry};
}
$('#btn-preview').onclick = async () => {
  try {
    const r = await api('submit', submitBody(true));
    modal('Generated sbatch scripts (dry run)', r.scripts.map(s => `<h3>${esc(s.name)}</h3><pre class="result">${esc(s.text)}</pre>`).join('') || '<p>nothing to submit</p>');
  } catch (e) { toast(e.message, true); }
};
$('#btn-submit').onclick = async () => {
  if (!S.project) return toast('Select a project', true);
  if (!S.pairs.length) return toast('No subjects selected', true);
  const steps = selectedModules(), prop = $('#do-propagate').checked;
  if (!steps.length && !prop) return toast('Select propagate and/or at least one P2 module', true);
  const notProp = S.pairs.filter(p => !p.propagated).length;
  const loc = document.querySelector('input[name=executor]:checked').value === 'local';
  let msg = (loc ? `Run ${S.pairs.length} job(s) for ${S.project} in the background on ${S.state.host}` + ($('#local-serial').checked ? ' (one at a time)' : ' (all at once)') + '?\n\n'
                 : `Submit ${S.pairs.length} job(s) for ${S.project}?\n\n`) + (prop ? '• propagate_scans (1 job)\n' : '') + (steps.length ? `• P2 ${steps.join(' ')} (${S.pairs.length} jobs)\n` : '');
  if (!prop && notProp) msg += `\nWARNING: ${notProp} selected subject(s) are not propagated yet and will fail in P2.`;
  const d1 = S.pairs.filter(p => p.day1);
  if (d1.length) msg += `\n• day1_path will be set for ${d1.length} session(s): ` + d1.map(p => `${p.sid} → ${p.day1}`).join(', ');
  if (d1.length && steps.length && !steps.includes('-reg') && !d1.every(p => (S.overview?.rows || []).find(r => r.id === p.sid)?.modules?.['-reg']?.state === 'done'))
    msg += `\nWARNING: later-day sessions need -reg (prepares day-1 masks) before -BOLD; -reg is not selected.`;
  if (!confirm(msg)) return;
  const btn = $('#btn-submit'); btn.disabled = true;
  try {
    const r = await api('submit', submitBody(false));
    const out = $('#submit-result'); out.classList.remove('hidden');
    out.innerHTML = r.submitted.map(j => `<span class="ok">submitted</span> ${esc(j.job_id)}  ${esc(j.name)}${j.dependency ? '  (after ' + esc(j.dependency) + ')' : ''}${j.note ? '  <span class="muted">' + esc(j.note) + '</span>' : ''}`).join('\n')
      + (r.errors.length ? '\n' + r.errors.map(e => `<span class="err">ERROR</span> ${esc(e)}`).join('\n') : '');
    toast(`${r.submitted.length} job(s) submitted${r.errors.length ? ', ' + r.errors.length + ' error(s)' : ''}`, r.errors.length > 0);
    S.pairs.forEach(p => p.propagated = p.propagated || prop); renderPairs();
  } catch (e) { toast(e.message, true); }
  btn.disabled = false;
};

// ---------------------------------------------------------------- STATUS
async function loadProject(silent) {
  if (!S.project) { $('#status-empty').classList.remove('hidden'); return; }
  try {
    S.overview = await api('project?name=' + encodeURIComponent(S.project));
    renderStatus();
  } catch (e) { if (!silent) toast(e.message, true); }
}
$('#status-filter').oninput = renderStatus; $('#status-only-scans').onchange = renderStatus;
function displayedModules() {
  const def = S.state.config.default_steps || [];
  const used = new Set(def);
  for (const r of (S.overview?.rows || [])) for (const [f, m] of Object.entries(r.modules || {})) if (m.state !== 'none') used.add(f);
  const pref = S.state.config.step_order || [];
  return S.state.modules.filter(m => used.has(m.flag)).sort((a, b) => (pref.indexOf(a.flag) + 1 || 99) - (pref.indexOf(b.flag) + 1 || 99));
}
function renderStatus() {
  const ov = S.overview; if (!ov) return;
  const mods = displayedModules();
  const thead = $('#status-table thead');
  thead.innerHTML = `<tr><th><input type="checkbox" id="st-all"></th><th>Subject / session</th><th>Scans</th><th>Prop.</th><th>params</th><th title="day1_path">Day 1</th>` +
    mods.map(m => `<th class="cell" title="${esc(m.desc)}">${esc(m.flag)}</th>`).join('') +
    `<th>Outputs</th><th>Last activity</th><th>Job</th><th>Last result</th><th></th></tr>`;
  const f = $('#status-filter').value.toLowerCase(), onlyScans = $('#status-only-scans').checked;
  const tb = $('#status-table tbody'); tb.innerHTML = '';
  const counts = {done: 0, failed: 0, running: 0, interrupted: 0, total: 0};
  for (const r of ov.rows) {
    if (onlyScans && !r.in_scans) continue;
    const states = mods.map(m => r.modules?.[m.flag]?.state || 'none');
    const text = [r.id, ...states, r.job?.state, r.last_run?.result].join(' ').toLowerCase();
    if (f && !text.includes(f)) continue;
    counts.total++;
    if (states.includes('running')) counts.running++; else if (states.includes('failed')) counts.failed++;
    else if (states.includes('interrupted')) counts.interrupted++;
    if (mods.length && mods.every(m => (r.modules?.[m.flag]?.state) === 'done')) counts.done++;
    const outs = Object.entries(r.outputs || {}).filter(([k, v]) => v).map(([k]) => k);
    const lr = r.last_run;
    tb.insertAdjacentHTML('beforeend', `<tr class="clickable" data-sid="${esc(r.id)}">
      <td><input type="checkbox" class="st-sel" data-sid="${esc(r.id)}" data-sub="${esc(r.subject)}" data-ses="${esc(r.session)}"></td>
      <td><b>${esc(r.id)}</b>${r.locked ? ' <span title=".inprocess lock present">🔒</span>' : ''}</td>
      <td>${r.in_scans ? '✓' : '<span class="muted">–</span>'}</td><td>${r.propagated ? '✓' : '<span class="err">–</span>'}</td>
      <td>${r.params ? '✓' : (r.propagated ? '<span class="err">missing</span>' : '')}</td>
      <td class="muted">${esc(r.day1 || '')}</td>` +
      mods.map(m => { const s = r.modules?.[m.flag] || {state: 'none'}; return `<td class="cell" title="${esc(m.flag)}: ${esc(s.state)} ${esc(s.when || '')}"><i class="st ${esc(s.state)}"></i></td>`; }).join('') +
      `<td class="muted" title="output files detected">${esc(outs.join(' '))}</td><td class="muted">${esc(r.last_activity || '')}</td>
      <td>${r.job ? pill(r.job.state) + ' <span class="muted">' + esc(r.job.job_id) + '</span>' : ''}</td>
      <td>${lr ? `<span class="${lr.result === 'success' ? 'ok' : lr.result === 'failed' ? 'err' : 'muted'}">${esc(lr.result)}</span> <span class="muted">${esc(lr.errors[0] || lr.modules.join(' '))}</span>` : '<span class="muted">never run</span>'}</td>
      <td><button class="ghost small" data-open="${esc(r.id)}">details</button></td></tr>`);
  }
  $('#status-counts').innerHTML = `<span class="counts"><span>${counts.total} shown</span><span class="ok">${counts.done} complete</span><span class="err">${counts.failed} failed</span><span style="color:var(--running)">${counts.running} running</span><span style="color:var(--interrupted)">${counts.interrupted} interrupted</span></span>`;
  $('#status-empty').classList.toggle('hidden', ov.rows.length > 0);
  tb.querySelectorAll('tr.clickable').forEach(tr => tr.onclick = e => { if (e.target.closest('input,button')) return; openSubject(tr.dataset.sid); });
  tb.querySelectorAll('button[data-open]').forEach(b => b.onclick = () => openSubject(b.dataset.open));
  $('#st-all').onchange = e => $$('.st-sel').forEach(c => c.checked = e.target.checked);
}
$('#btn-select-status').onclick = () => {
  const sel = $$('.st-sel').filter(c => c.checked);
  if (!sel.length) return toast('Tick some rows first', true);
  $('#sublist').value = sel.map(c => c.dataset.ses ? `${c.dataset.sub} ${c.dataset.ses}` : c.dataset.sub).join('\n');
  showTab('run'); parseList();
};
$('#btn-export-status').onclick = async () => {
  if (!S.project) return toast('Select a project', true);
  try { const r = await api('export_status', {project: S.project}); modal('Processing status saved', `<p>${r.rows} rows written to:</p><pre class="result">${esc(r.paths.join('\n'))}</pre><p><a href="${fileUrl(r.paths[0], true)}">download a copy</a></p>`); }
  catch (e) { toast(e.message, true); }
};

// ---------------------------------------------------------------- JOBS
async function loadJobs(silent) {
  try {
    const q = $('#jobs-this-project').checked && S.project ? '?project=' + encodeURIComponent(S.project) : '';
    const r = await api('jobs' + q); S.jobs = r.jobs; S.queue = r.queue; renderJobs();
  } catch (e) { if (!silent) toast(e.message, true); }
}
$('#jobs-this-project').onchange = () => loadJobs(); $('#jobs-active-only').onchange = renderJobs;
const ACTIVE = new Set(['PENDING', 'RUNNING', 'CONFIGURING', 'COMPLETING', 'SUSPENDED', 'REQUEUED']);
function renderJobs() {
  const tb = $('#jobs-table tbody'); tb.innerHTML = '';
  const act = $('#jobs-active-only').checked;
  for (const j of S.jobs) {
    if (act && !ACTIVE.has(j.state)) continue;
    const outs = (j.out_dir ? `<button class="ghost small" data-log="${esc(j.out_dir)}" data-jid="${esc(j.job_id)}" data-sid="${esc(j.sid)}" data-kind="${esc(j.kind)}">out</button>` : '');
    tb.insertAdjacentHTML('beforeend', `<tr><td>${esc(j.job_id)}</td><td>${j.sid ? `<a href="#" data-open="${esc(j.sid)}">${esc(j.sid)}</a>` : (j.pairs ? j.pairs.length + ' subj.' : '')}</td>
      <td>${esc(j.kind)} <span class="muted">${esc((j.steps || []).join(' '))} ${esc((j.overrides || []).join(' '))}</span></td>
      <td>${pill(j.state)}</td><td>${esc(j.elapsed || '')}</td><td class="muted">${esc(j.submitted)}</td><td>${esc(j.exit || '')}</td><td class="muted">${esc(j.reason || j.note || '')}</td>
      <td>${outs} <button class="ghost small" data-script="${esc(j.script)}">script</button> ${ACTIVE.has(j.state) ? `<button class="ghost small danger" data-cancel="${esc(j.job_id)}">cancel</button>` : ''}</td></tr>`);
  }
  tb.querySelectorAll('[data-cancel]').forEach(b => b.onclick = async () => { if (!confirm('scancel ' + b.dataset.cancel + '?')) return; try { const r = await api('cancel', {job_id: b.dataset.cancel}); toast(r.message); loadJobs(); } catch (e) { toast(e.message, true); } });
  tb.querySelectorAll('[data-script]').forEach(b => b.onclick = () => showFile(b.dataset.script, 'sbatch script'));
  tb.querySelectorAll('[data-open]').forEach(a => a.onclick = e => { e.preventDefault(); openSubject(a.dataset.open); });
  tb.querySelectorAll('[data-log]').forEach(b => b.onclick = () => {
    const j = S.jobs.find(x => x.job_id === b.dataset.jid) || {};
    const base = j.log_base || (b.dataset.kind === 'propagate' ? 'propagate_' : b.dataset.sid.replace(/[^A-Za-z0-9_.-]+/g, '_') + '_P2_');
    showFile(`${b.dataset.log}/${base}${b.dataset.jid}.out`, 'sbatch output ' + b.dataset.jid, `${b.dataset.log}/${base}${b.dataset.jid}.err`);
  });
  const qb = $('#queue-table tbody'); qb.innerHTML = S.queue.map(q => `<tr><td>${esc(q.job_id)}</td><td>${esc(q.name)}</td><td>${pill(q.state)}</td><td>${esc(q.time)}</td><td>${esc(q.partition || '')}</td><td class="muted">${esc(q.reason)}</td></tr>`).join('') || '<tr><td colspan="6" class="muted">queue empty</td></tr>';
}
$('#btn-cancel-all').onclick = async () => {
  const act = S.jobs.filter(j => ACTIVE.has(j.state) && (!S.project || j.project === S.project));
  if (!act.length) return toast('no active jobs');
  if (!confirm(`Cancel ${act.length} job(s)?`)) return;
  for (const j of act) { try { await api('cancel', {job_id: j.job_id}); } catch (e) { toast(e.message, true); } }
  loadJobs();
};
async function showFile(path, title, errPath) {
  try {
    const r = await api('tail?n=400&path=' + encodeURIComponent(path));
    let html = `<p class="muted">${esc(r.path)} ${r.size != null ? '(' + r.size + ' bytes, last ' + r.lines.length + ' lines)' : ''} <a href="${fileUrl(path)}" target="_blank">open</a></p><pre class="log">${esc(r.error || r.lines.join('\n'))}</pre>`;
    if (errPath) { const e = await api('tail?n=200&path=' + encodeURIComponent(errPath)); if (!e.error && e.lines.length) html += `<h3>stderr</h3><pre class="log">${esc(e.lines.join('\n'))}</pre>`; }
    modal(title, html);
  } catch (e) { toast(e.message, true); }
}

// ---------------------------------------------------------------- QC table
async function loadQC() {
  if (!S.project) return;
  try { const r = await api('qc_table?project=' + encodeURIComponent(S.project)); S.qcRows = r.rows; S.qcLabels = r.labels; S.fdThr = r.fd_threshold; renderQC(); } catch (e) { toast(e.message, true); }
}
function qcLabel(k) { const l = (S.qcLabels || []).find(x => x.key === k); return l ? l.label : k; }
function renderQCHead() {
  const head = $('#qc-head');
  head.innerHTML = (S.qcLabels || []).map(l => `<th data-k="${esc(l.key)}" title="${esc(l.help)}">${esc(l.label)}</th>`).join('') + '<th title="per run: % of frames kept after FD censoring">Per-run % frames kept</th>';
  head.querySelectorAll('th[data-k]').forEach(th => th.onclick = () => { const k = th.dataset.k; S.qcSort = {k, dir: S.qcSort.k === k ? -S.qcSort.dir : 1}; renderQC(); });
}
function renderQC() {
  renderQCHead();
  const {k, dir} = S.qcSort;
  const rows = [...S.qcRows].sort((a, b) => { const x = a[k], y = b[k]; if (x == null) return 1; if (y == null) return -1; return (x > y ? 1 : x < y ? -1 : 0) * dir; });
  const fmt = v => v == null ? '<span class="muted">–</span>' : v;
  const warn = (v, thr, hi) => v == null ? fmt(v) : `<span class="${hi ? (v > thr ? 'err' : '') : (v < thr ? 'err' : '')}">${v}</span>`;
  $('#qc-table tbody').innerHTML = rows.map(r => `<tr class="clickable" data-sid="${esc(r.sid)}"><td><b>${esc(r.sid)}</b></td><td>${fmt(r.runs)}</td><td>${fmt(r.good_frames)}</td><td>${fmt(r.bad_frames)}</td>
    <td>${r.pct_good != null ? `<span class="progress"><i style="width:${r.pct_good}%"></i></span>` : ''}${warn(r.pct_good, 70, false)}</td><td>${fmt(r.minutes_good)}</td>
    <td>${warn(r.mean_rms, 0.3, true)}</td><td>${warn(r.max_rms, 0.5, true)}</td><td>${fmt(r.sd_pre)}</td><td>${fmt(r.sd_post)}</td>
    <td class="muted">${(r.fd_runs || []).map(x => x.pct + '%').join(' · ')}</td></tr>`).join('') || '<tr><td colspan="11" class="muted">no QC metrics found (run -QC)</td></tr>';
  $$('#qc-table tr.clickable').forEach(tr => tr.onclick = () => openSubject(tr.dataset.sid, false, 'qc'));
}
$('#btn-render-surf').onclick = async () => {
  if (!S.project) return toast('Select a project', true);
  const n = S.qcRows.length;
  if (!confirm(`Render tSNR (0-130) and SD (0-12) surface images for ${n} session(s) of ${S.project}?\nRuns wb_command on this node (~10-30 s per image).`)) return;
  try { await api('surface_qc', {project: S.project, only_missing: $('#render-missing').checked}); pollRender(); }
  catch (e) { toast(e.message, true); }
};
async function pollRender() {
  const el = $('#render-status');
  try {
    const st = await api('surface_qc_status');
    el.textContent = st.done ? `rendering done: ${st.ok} rendered, ${st.skipped} already present, ${st.failed.length} failed (${st.elapsed}s)`
                             : `rendering ${st.completed}/${st.total} … ${st.current}`;
    if (!st.done) setTimeout(pollRender, 3000);
    else if (st.failed.length) modal('Some renderings failed', `<pre class="result">${esc(st.failed.map(f => `${f.sid} ${f.metric}: ${f.error}`).join('\n'))}</pre>`);
  } catch (e) { el.textContent = e.message; }
}
$('#btn-qc-report').onclick = async () => {
  if (!S.project) return toast('Select a project', true);
  try { const r = await api('qc_report', {project: S.project});
    modal('QC report written', `<p>${esc(r.path)} (${(r.size / 1e6).toFixed(1)} MB)</p><p><a href="${fileUrl(r.path)}" target="_blank">open in a new tab</a> · <a href="${fileUrl(r.path, true)}">download</a></p><p class="muted">Sessions without rendered surface images show a placeholder — use "Render surface images" first.</p>`); }
  catch (e) { toast(e.message, true); }
};
$('#btn-export-qc').onclick = async () => {
  if (!S.project) return toast('Select a project', true);
  try { const r = await api('export_qc', {project: S.project}); modal('QC summary saved', `<p>${r.rows} rows written to:</p><pre class="result">${esc(r.paths.join('\n'))}</pre><p><a href="${fileUrl(r.paths[0], true)}">download a copy</a></p>`); }
  catch (e) { toast(e.message, true); }
};

// ---------------------------------------------------------------- STUDY.cfg
let studyState = null;
async function loadStudy(projectOverride) {
  const proj = projectOverride || S.project; if (!proj) return;
  try {
    studyState = await api('studycfg?project=' + encodeURIComponent(proj)); studyState.project = proj;
    $('#study-path').textContent = `${S.state.config.projects_root}/${proj}/Study.cfg` + (studyState.exists ? '' : ' (does not exist yet)');
    $('#study-missing').classList.toggle('hidden', studyState.exists);
    const cur = Object.fromEntries(studyState.entries.map(e => [e.name, e.value]));
    const names = [...studyState.defaults.map(d => d.name), ...studyState.entries.map(e => e.name).filter(n => !studyState.defaults.some(d => d.name === n))];
    const form = $('#study-form'); form.innerHTML = '';
    for (const n of names) {
      const d = studyState.defaults.find(x => x.name === n) || {value: '', help: ''};
      let v = cur[n] ?? d.value;
      if (!studyState.exists) {
        if (n === 'ScratchFolder' && !v) v = studyState.scratch_default;
        if (n === 'target' && !v && studyState.atlases.length) v = studyState.atlases[0];
        if (n === 'StudyGroup') v = S.state.config.study_group || v;
        if (n === 'UserEmailAddress' && !v) v = S.state.config.notify_email || '';
      }
      let input;
      if (n === 'TargetAtlas' && studyState.atlases.length)
        input = `<select data-k="${n}">${studyState.atlases.map((a, i) => `<option value="${i + 1}" ${String(i + 1) === String(v) ? 'selected' : ''}>${i + 1}: ${esc(a)}</option>`).join('')}<option value="0" ${String(v) === '0' ? 'selected' : ''}>0: native T1 space</option></select>`;
      else if (n === 'FreesurferVersionToUse' && S.state.fs_versions.length)
        input = `<select data-k="${n}">${S.state.fs_versions.map(f => `<option ${f === v ? 'selected' : ''}>${esc(f)}</option>`).join('')}</select>`;
      else input = `<input data-k="${n}" value="${esc(v)}">`;
      form.insertAdjacentHTML('beforeend', `<label title="${esc(d.help)}">${esc(n)} <span class="muted">${esc(d.help)}</span>${input}</label>`);
    }
    form.querySelector('select[data-k=TargetAtlas]')?.addEventListener('change', e => { const i = +e.target.value; const t = form.querySelector('[data-k=target]'); if (t && i > 0) t.value = studyState.atlases[i - 1]; });
    $('#study-raw').classList.add('hidden');
  } catch (e) { toast(e.message, true); }
}
$('#btn-study-raw').onclick = () => { const p = $('#study-raw'); p.textContent = studyState?.raw || '(none)'; p.classList.toggle('hidden'); };
$('#btn-study-save').onclick = async () => {
  if (!studyState) return;
  const values = {}; $$('#study-form [data-k]').forEach(i => values[i.dataset.k] = i.value);
  const create = !studyState.project_dir_exists;
  if (!confirm(`${studyState.exists ? 'Overwrite (backup kept as Study.cfg.bak)' : 'Create'} Study.cfg for ${studyState.project}?` + (create ? '\nThe project folder structure will be created.' : ''))) return;
  try { const r = await api('save_studycfg', {project: studyState.project, values, create}); toast('saved ' + r.path); if (r.created.length) modal('Created', `<pre class="result">${esc(r.created.join('\n'))}</pre>`);
    S.state = await api('state'); loadStudy(); } catch (e) { toast(e.message, true); }
};
$('#btn-new-project').onclick = async () => {
  const name = prompt('Project name (must match the folder name in Scans/, e.g. Anhedonia):', S.project || '');
  if (!name) return;
  const names = Array.from(new Set([...S.state.projects, ...S.state.scan_projects]));
  if (!names.includes(name)) { const sel = $('#project'); sel.insertAdjacentHTML('beforeend', `<option value="${esc(name)}">${esc(name)} (new)</option>`); }
  $('#project').value = name; S.project = name; localStorage.setItem('unp.project', name); S.pairs = []; renderPairs();
  showTab('study');
};

// ---------------------------------------------------------------- SETTINGS
function fillSettings() {
  const c = S.state.config;
  const get = k => k.split('.').reduce((o, p) => (o || {})[p], c);
  $$('[id^="c-"]').forEach(el => {
    const k = el.id.slice(2); let v = get(k);
    if (el.type === 'checkbox') el.checked = !!v; else if (Array.isArray(v)) el.value = v.join(k === 'qc_extra_fd_thresholds' ? ', ' : '\n'); else el.value = v ?? '';
  });
  const e = c.env || {};
  $('#env-info').innerHTML = `From <code>${esc(c.env_script)}</code>: PROJECTS_HOME=<code>${esc(e.PROJECTS_HOME || '?')}</code> SCRATCH=<code>${esc(e.SCRATCH || '?')}</code> PP_SCRIPTS=<code>${esc(c.pp_scripts)}</code><br>
    sbatch ${c.sbatch_available ? 'found' : '<span class="err">NOT found</span>'} · sg ${c.sg_available ? 'found' : '<span class="err">NOT found</span>'} · numpy ${S.state.numpy ? 'available (NIfTI montages on)' : 'missing (montages off)'}<br>GUI dir: <code>${esc(c.gui_root)}</code>`;
}
$('#btn-slurm-check').onclick = async () => {
  try { const r = await api('slurm_check'); $('#partitions-info').textContent =
    `sbatch --version -> rc=${r.sbatch_rc}: ${r.sbatch_out}\nsinfo -> rc=${r.sinfo_rc}: ${r.partitions.join(' ') || r.sinfo_err}\nbin dir: ${r.bin_dir || '(PATH)'}   prefix: ${r.prefix.join(' ') || '(none)'}   bin dir: ${r.bin_dir || '(none)'}   fake: ${r.fake}\nlogin node: ${r.ssh_host || '(none)'}   ssh connection open: ${r.ssh_master === null ? 'n/a' : r.ssh_master}\n${r.which}`; }
  catch (e) { toast(e.message, true); }
};
$('#btn-settings-save').onclick = async () => {
  const body = {slurm: {}};
  $$('[id^="c-"]').forEach(el => {
    const k = el.id.slice(2); let v = el.type === 'checkbox' ? el.checked : el.value;
    if (['job_prologue', 'slurm.extra_sbatch'].includes(k)) v = v.split('\n').map(s => s.trim()).filter(Boolean);
    if (k === 'qc_extra_fd_thresholds') v = v.split(/[,\s]+/).map(Number).filter(x => x > 0);
    if (k === 'slurm_cmd_prefix') v = v.trim() ? v.trim().split(/\s+/) : [];
    if (el.type === 'number') v = +v;
    if (k.startsWith('slurm.')) body.slurm[k.slice(6)] = v; else body[k] = v;
  });
  try { await api('config_save', body); toast('settings saved – reloading'); setTimeout(() => location.reload(), 600); } catch (e) { toast(e.message, true); }
};

// ---------------------------------------------------------------- subject drawer
function closeDrawer() { $('#drawer').classList.add('hidden'); S.drawerSid = null; }
$('#drawer-close').onclick = closeDrawer;
$$('.subtabs button').forEach(b => b.onclick = () => showSub(b.dataset.sub));
function showSub(name) { $$('.subtabs button').forEach(b => b.classList.toggle('active', b.dataset.sub === name)); $$('.drawer-body .sub').forEach(s => s.classList.toggle('active', s.id === 'd-' + name)); }
$('#drawer-unlock').onclick = async () => { if (!confirm('Remove .inprocess lock for ' + S.drawerSid + '? Only do this if no P2 is really running on it.')) return; try { const r = await api('unlock', {project: S.project, sid: S.drawerSid}); toast(r.message); openSubject(S.drawerSid, true); loadProject(true); } catch (e) { toast(e.message, true); } };
$('#drawer-torun').onclick = () => { const d = S.drawerData; $('#sublist').value = d.id; closeDrawer(); showTab('run'); parseList(); };
async function openSubject(sid, silent, sub) {
  try {
    const d = await api(`subject?project=${encodeURIComponent(S.project)}&sid=${encodeURIComponent(sid)}`);
    S.drawerSid = sid; S.drawerData = d;
    $('#drawer').classList.remove('hidden');
    $('#drawer-title').textContent = sid; $('#drawer-sub').textContent = d.dir;
    $('#drawer-unlock').classList.toggle('hidden', !d.locked);
    renderOverview(d); renderLogs(d); renderQCsub(d); renderImages(d); renderParams(d);
    if (sub) showSub(sub); else if (!silent) showSub('overview');
  } catch (e) { if (!silent) toast(e.message, true); }
}
function renderOverview(d) {
  const mods = S.state.modules.filter(m => d.modules[m.flag] && d.modules[m.flag].state !== 'none' || (S.state.config.default_steps || []).includes(m.flag));
  let html = `<div class="kv"><b>Folder exists</b><span>${d.exists ? 'yes' : '<span class="err">no – not propagated</span>'}</span>
    <b>params</b><span>${d.params ? esc(d.params_path) : '<span class="err">missing</span>'}</span>
    <b>Day 1 session</b><span id="d-day1">${d.params ? (d.day1 ? '<code>' + esc(d.day1) + '</code>' : 'this session is day 1') + ' <button class="ghost small" id="d-day1-edit">change</button>' : '<span class="muted">(no params yet)</span>'}</span>
    <b>Lock</b><span>${d.locked ? '🔒 .inprocess present' : 'none'}</span>
    <b>GUI job</b><span>${d.job ? pill(d.job.state) + ' ' + esc(d.job.job_id) + ' <span class="muted">' + esc((d.job.steps || []).join(' ')) + ' submitted ' + esc(d.job.submitted) + '</span>' : '<span class="muted">none</span>'}</span>
    <b>Last command</b><span><code>${esc(d.last_command || '–')}</code></span>
    <b>Outputs found</b><span>${Object.entries(d.outputs || {}).map(([k, v]) => `<span class="pill ${v ? 'done' : 'none'}">${k}</span>`).join(' ')}</span></div>`;
  html += `<h3>Module status</h3><table class="compact"><thead><tr><th>Module</th><th>State</th><th>When</th><th>Log</th></tr></thead><tbody>` +
    mods.map(m => { const s = d.modules[m.flag] || {state: 'none'}; return `<tr><td><code>${esc(m.flag)}</code> <span class="muted">${esc(m.desc.slice(0, 70))}</span></td><td>${pill(s.state)}</td><td>${esc(s.when || '')}</td><td>${s.log ? `<button class="ghost small" data-tail="${esc(s.log)}">tail</button>` : ''}</td></tr>`; }).join('') + '</tbody></table>';
  if (d.last_run) html += `<h3>Last run</h3><div class="kv"><b>Started</b><span>${esc(d.last_run.started)}</span><b>Modules</b><span>${esc(d.last_run.modules.join(' '))}</span><b>Result</b><span class="${d.last_run.result === 'success' ? 'ok' : 'err'}">${esc(d.last_run.result)}</span><b>Errors</b><span>${esc(d.last_run.errors.join('; ') || '–')}</span><b>Summary file</b><span><button class="ghost small" data-tail="${esc(d.last_run.file)}">view</button></span></div>`;
  if (d.history?.length) html += `<h3>Execution history</h3><pre class="log">${esc(d.history.join('\n'))}</pre>`;
  $('#d-overview').innerHTML = html;
  $('#d-overview').querySelectorAll('[data-tail]').forEach(b => b.onclick = () => tailInto(b.dataset.tail, '#d-logs') || showSub('logs'));
  const eb = $('#d-day1-edit'); if (eb) eb.onclick = () => editDay1(d);
}
async function editDay1(d) {
  try {
    const r = await api(`day1?project=${encodeURIComponent(S.project)}&sid=${encodeURIComponent(d.id)}`);
    const p = {sid: d.id, day1: r.day1, day1_candidates: r.candidates, day1_suggested: ''};
    $('#d-day1').innerHTML = day1Select(p, 'day1-drawer') + ` <button class="primary small" id="d-day1-apply">apply</button> <button class="ghost small" id="d-day1-cancel">cancel</button>`;
    $('#d-day1-cancel').onclick = () => renderOverview(d);
    $('#d-day1-apply').onclick = async () => {
      const day1 = $('#d-day1 select').value;
      if (!confirm(day1 ? `Set day1_path of ${d.id} to InProcess/${day1}? (backup kept as .params.day1.bak)` : `Clear day1_path of ${d.id} (make it a day-1 session)?`)) return;
      try { const rr = await api('set_day1', {project: S.project, sid: d.id, day1}); toast(rr.warning || 'params updated' , !!rr.warning); openSubject(d.id, true); loadProject(true); }
      catch (e) { toast(e.message, true); }
    };
  } catch (e) { toast(e.message, true); }
}
function renderLogs(d) {
  const box = $('#d-logs');
  let html = '<div class="loglist">' + (d.logs || []).map(l => `<button data-tail="${esc(l.path)}" title="${esc(l.mtime)} ${l.size} B">${esc(l.name.replace('Processing_Summary_', 'Summary '))}</button>`).join('') + '</div>';
  if (d.sbatch_logs?.length) html += '<div class="loglist"><span class="muted">sbatch:</span>' + d.sbatch_logs.map(l => `<button data-tail="${esc(l.path)}">${esc(l.name)}</button>`).join('') + '</div>';
  html += '<div id="d-logview"><p class="muted">Select a log. Showing the last 400 lines; “open” shows the full file.</p></div>';
  box.innerHTML = html;
  box.querySelectorAll('[data-tail]').forEach(b => b.onclick = () => tailInto(b.dataset.tail));
}
async function tailInto(path) {
  showSub('logs');
  const v = $('#d-logview'); v.innerHTML = '<p class="muted">loading…</p>';
  try { const r = await api('tail?n=400&path=' + encodeURIComponent(path));
    v.innerHTML = `<p class="muted">${esc(r.path)} · ${r.size} bytes · <a href="${fileUrl(path)}" target="_blank">open full file</a></p><pre class="log">${esc(r.error || r.lines.join('\n'))}</pre>`;
    v.querySelector('pre').scrollTop = 1e9; } catch (e) { v.innerHTML = `<p class="err">${esc(e.message)}</p>`; }
  return true;
}
function renderQCsub(d) {
  const m = d.metrics || {}; let html = '';
  if (m.summary && Object.keys(m.summary).length) html += `<div class="kv">${Object.entries(m.summary).map(([k, v]) => `<b>${esc(qcLabel(k))}</b><span>${esc(v)}</span>`).join('')}</div>`;
  if (m.fd_runs?.length) { const fx = m.fd_extra || {}; const thrs = Object.keys(fx);
    html += `<h3>Motion censoring per BOLD run</h3><table class="compact"><thead><tr><th>Run</th><th>Frames censored (study FD)</th><th>Frames kept</th><th>% frames kept</th><th>Seconds kept</th><th>RMS head motion (mm/frame)</th>${thrs.map(t => `<th>% kept (FD &lt; ${esc(t)} mm)</th>`).join('')}</tr></thead><tbody>${m.fd_runs.map((r, i) => `<tr><td>${r.run}</td><td>${r.bad}</td><td>${r.good}</td><td><span class="progress"><i style="width:${r.pct}%"></i></span>${r.pct}</td><td>${r.sec}</td><td>${m.rms?.[i] ?? ''}</td>${thrs.map(t => `<td>${fx[t].runs[i]?.pct ?? ''}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
    if (thrs.length) html += `<p class="muted">Extra-threshold counts are recomputed from <code>Functional/Movement/bold*_upck_faln_dbnd_xr3d.ddat.fd</code> (same rule as the pipeline: frame kept if FD &lt; threshold, first ${esc(String(fx[thrs[0]].skip))} frames excluded, TR ${esc(String(fx[thrs[0]].tr))} s).</p>`; }
  if (m.pet?.length) html += `<h3>PET QC</h3><pre class="log">${esc(JSON.stringify(m.pet, null, 1))}</pre>`;
  if (m.files?.length) html += `<h3>QC folder</h3><div class="loglist">${m.files.map(f => f.kind === 'image' ? `<button data-img="${esc(f.path)}">${esc(f.name)}</button>` : f.kind === 'text' ? `<button class="ghost" data-tail="${esc(f.path)}">${esc(f.name)}</button>` : `<a class="muted" href="${fileUrl(f.path, true)}">${esc(f.name)}</a>`).join('')}</div>`;
  if (!html) html = '<p class="muted">No QC metrics yet (run -QC).</p>';
  $('#d-qc').innerHTML = html;
  $('#d-qc').querySelectorAll('[data-tail]').forEach(b => b.onclick = () => tailInto(b.dataset.tail));
  $('#d-qc').querySelectorAll('[data-img]').forEach(b => b.onclick = () => { showSub('images'); showImage(b.dataset.img); });
}
function renderImages(d) {
  const m = d.metrics || {}; const imgs = (m.files || []).filter(f => f.kind === 'image');
  let html = '<div class="loglist">' + imgs.map(f => `<button data-img="${esc(f.path)}">${esc(f.name)}</button>`).join('') + '</div>';
  if (d.volumes?.length) html += `<div class="loglist"><span class="muted">volumes${S.state.numpy ? '' : ' (numpy missing – montage disabled)'}:</span>` + d.volumes.map(v => `<button ${S.state.numpy ? '' : 'disabled'} data-vol="${esc(v.path)}">${esc(v.label)}</button>`).join('') + '</div>';
  html += '<div id="d-imgview" class="imgs"><p class="muted">Pick an image or volume above.</p></div>';
  $('#d-images').innerHTML = html;
  $('#d-images').querySelectorAll('[data-img]').forEach(b => b.onclick = () => showImage(b.dataset.img));
  $('#d-images').querySelectorAll('[data-vol]').forEach(b => b.onclick = () => showVolume(b.dataset.vol, b.textContent));
}
function showImage(path) {
  const v = $('#d-imgview');
  if (/\.pdf$/i.test(path)) v.innerHTML = `<p class="muted">${esc(path)} · <a href="${fileUrl(path)}" target="_blank">open in new tab</a></p><iframe class="pdf" src="${fileUrl(path)}"></iframe>`;
  else v.innerHTML = `<p class="muted">${esc(path)}</p><div class="thumb"><img src="${fileUrl(path)}"></div>`;
}
function showVolume(path, label) {
  const v = $('#d-imgview');
  v.innerHTML = `<p class="muted">${esc(label)} · ${esc(path)} · axis <button class="ghost small" data-ax="2">axial</button><button class="ghost small" data-ax="1">coronal</button><button class="ghost small" data-ax="0">sagittal</button></p><div class="thumb"><img id="montage" src="/api/montage?axis=2&path=${encodeURIComponent(path)}" onerror="this.alt='could not render (numpy missing or unreadable file)'"></div>`;
  v.querySelectorAll('[data-ax]').forEach(b => b.onclick = () => $('#montage').src = `/api/montage?axis=${b.dataset.ax}&path=${encodeURIComponent(path)}`);
}
function renderParams(d) {
  const box = $('#d-params');
  if (!d.params) { box.innerHTML = '<p class="muted">No params file.</p>'; return; }
  box.innerHTML = `<div class="row"><span class="muted">${esc(d.params_path)}</span><div class="spacer"></div><button class="primary small" id="save-params">Save params (backup kept)</button></div><textarea class="params">${esc(d.params_text)}</textarea>`;
  $('#save-params').onclick = async () => { if (!confirm('Overwrite ' + d.params_path + '?')) return; try { await api('save_params', {path: d.params_path, text: box.querySelector('textarea').value}); toast('params saved'); } catch (e) { toast(e.message, true); } };
}

// ---------------------------------------------------------------- PFM: template matching + subcortical WTA
S.tm = null;
async function loadTM() {
  if (!S.project) return;
  try { S.tm = await api('tm_overview?project=' + encodeURIComponent(S.project)); renderTM(); } catch (e) { toast(e.message, true); }
}
function tmMode() { return document.querySelector('input[name=tm-mode]:checked').value; }
function tmFill() {
  const t = S.tm, c = S.state.config.slurm || {};
  const asel = $('#tm-atlas'); const prevA = asel.value;
  const aopts = t.atlas_options || Object.keys(t.atlases).map(k => ({key: k, label: k, usable: true}));
  asel.innerHTML = aopts.map(a => `<option value="${esc(a.key)}"${a.usable ? '' : ' disabled'} title="${esc(a.reason || a.path || '')}">${esc(a.label)}</option>`).join('');
  const okA = aopts.filter(a => a.usable).map(a => a.key);
  asel.value = okA.includes(prevA) ? prevA : (okA.includes(t.default_atlas) ? t.default_atlas : (okA[0] || ''));
  const pdl = $('#tm-parc-dir'); if (pdl) pdl.textContent = t.parcellation_dir || '';
  const vs = Array.from(new Set(t.rows.flatMap(r => r.variants))).sort();
  const vsel = $('#tm-variant'); const prevV = vsel.value;
  vsel.innerHTML = (vs.length > 1 ? '<option value="">— choose the timeseries to use —</option>' : '') +
    (vs.map(v => `<option value="${esc(v)}">${esc(v)}</option>`).join('') || `<option>${esc(t.default_variant)}</option>`);
  let savedV = ''; try { savedV = localStorage.getItem('unp-tm-variant') || ''; } catch (e) {}
  // never pick a timeseries silently: previous choice, remembered choice or the built-in default if the sessions have it, else ask
  const pickV = [prevV, savedV, t.default_variant].find(x => x && vs.includes(x));
  vsel.value = pickV || (vs.length > 1 ? '' : (vs[0] || t.default_variant));
  const msel = $('#tm-wta-method'); const prevM = msel.value;
  msel.innerHTML = Object.keys(t.wta_methods).map(m => `<option value="${esc(m)}">${esc(m)}</option>`).join(''); if (prevM) msel.value = prevM;
  $('#tm-wta-desc').textContent = t.wta_methods[msel.value] || '';
  $('#tm-groups').placeholder = msel.value === 'both' ? "default: each method's own (set one to use it for both)" : 'default: ' + (t.wta_defaults.groups[msel.value] || '');
  if (!$('#tm-partition').value) { $('#tm-partition').value = c.tm_partition || 'cpu_short'; $('#tm-cpus').value = c.tm_cpus || 4; $('#tm-mem').value = c.tm_mem || '150G'; $('#tm-time').value = c.tm_time || '12:00:00'; }
  $('#tm-script').textContent = t.script + (t.script_exists ? '' : '  (NOT FOUND)');
  $('#tm-name-wrap').style.display = tmMode() === 'concat' ? '' : 'none';
  $('#tm-wta-card').style.opacity = $('#tm-step-wta').checked ? 1 : .45;
  $$('#tm-wta-card input').forEach(i => i.disabled = !$('#tm-step-wta').checked);
  // smoothing applies to both methods (same wb_command call, so equal σ = comparable maps); top-% is scoresmoothing only
  $('#tm-top').disabled = !$('#tm-step-wta').checked || (msel.value !== 'scoresmoothing_v3' && msel.value !== 'both');
  $('#tm-mindist').disabled = $('#tm-top').disabled;      // distance exclusion: scoresmoothing only
  $('#tm-smooth').disabled = !$('#tm-step-wta').checked;
  $('#tm-nonorm').disabled = !$('#tm-step-wta').checked || msel.value === 'scoresmoothing_v3';   // networkseed only
}
// output-name suffix: same rule as tm.normalize_suffix / run_PFM.sh --suffix; null = invalid
function tmSuffix() {
  const s = ($('#tm-suffix').value || '').trim();
  if (!s) return '';
  if (!/^[A-Za-z0-9_.-]+$/.test(s)) return null;
  const n = /^[A-Za-z0-9]/.test(s) ? '_' + s : s;
  return n.includes('_TM_') ? null : n;
}
function tmSuffixFromVariant(v) { const s = (v || '').replace(/\.ctx$/, '').replace(/^uout_bpss_(sr_)?/, ''); return s ? '_' + s : ''; }
// suffix tokens that describe preprocessing (sm2, GSR, noGSR, ...) but are not in the input timeseries name
function tmSuffixWarning(sfx, variant) {
  if (!sfx || !variant) return '';
  const vt = new Set(variant.replace(/\.ctx$/, '').split(/[_.]/).map(x => x.toLowerCase()));
  const bad = sfx.split(/[_.-]/).filter(x => /^(sm\d+(p\d+)?|s\d+|nogsr|gsr|91206|91282)$/i.test(x) && !vt.has(x.toLowerCase()));
  return bad.length ? `"${bad.join('", "')}" is not part of the input timeseries name (${variant})` : '';
}
function tmOut(r, sfx) {
  return (r.outputs || {})[sfx] || (sfx === '' ? {name: r.sid, tm: r.tm || {}, dconn: r.dconn, status: r.status || []} : {name: r.sid + sfx, tm: {}, dconn: false, status: []});
}
function tmSuffixNote() {
  const sfx = tmSuffix(), el = $('#tm-suffix-note'); if (!el) return;
  if (sfx === null) { el.innerHTML = '<span class="err">invalid suffix: letters, digits, _ . - only, no _TM_</span>'; return; }
  const first = $$('.tm-sel').find(c => c.checked);
  const nm = tmMode() === 'concat' ? ($('#tm-name').value.trim() || '<Subject>_concat<N>') + sfx : (first ? first.dataset.sid : '<session>') + sfx;
  const w = tmSuffixWarning(sfx, $('#tm-variant').value);
  el.innerHTML = `outputs: <code>${esc(nm)}.dconn.nii</code>, <code>${esc(nm)}_TM_*</code>` + (w ? `<br><span class="err">check: ${esc(w)}</span>` : '');
}
$('#tm-suffix').oninput = () => renderTM();
$('#tm-suffix-auto').onclick = () => { $('#tm-suffix').value = tmSuffixFromVariant($('#tm-variant').value); renderTM(); };
$('#tm-name').oninput = () => tmSuffixNote();
$('#tm-atlas').onchange = () => renderTM(); $('#tm-variant').onchange = () => { try { localStorage.setItem('unp-tm-variant', $('#tm-variant').value); } catch (e) {} renderTM(); };
$('#tm-wta-method').onchange = () => tmFill(); $('#tm-step-wta').onchange = () => tmFill();
$$('input[name=tm-mode]').forEach(r => r.onchange = () => tmFill());
function tmResultCells(st, atlases, dir, outDir, name) {
  return Object.keys(atlases).map(a => { const x = st[a];
    if (!x) return '<td class="muted">–</td>';
    if (!x.done) return '<td><span class="pill interrupted">partial</span></td>';
    const wta = Object.entries(x.wta || {}).map(([m, w]) => `<br><span class="pill done">WTA</span> <span class="muted">${esc(m)}${w.cleaned ? '' : ' (no cleanup)'} ${esc(w.mtime)}</span>` +
      (w.csv ? ` <a href="#" data-csv="${esc(w.csv)}" data-atlas="${esc(a)}" data-name="${esc(name)}">by structure</a>` : '') +
      (w.png ? ` <a href="#" data-img="${esc(w.png)}">image</a>` : '')).join('');
    return `<td><span class="pill done">TM</span> <span class="muted">${esc(x.mtime)}</span>${x.png ? ` <a href="#" data-img="${esc(x.png)}">map</a>` : ''}${wta}</td>`; }).join('');
}
function tmStatusHtml(st) {
  if (!st || !st.length) return '';
  const last = st[st.length - 1];
  const bad = st.filter(x => x.result !== 'OK');
  return `<div class="muted" style="font-size:11px">last: ${esc(last.step)} ${last.result === 'OK' ? '<span class="ok">OK</span>' : '<span class="err">' + esc(last.result) + '</span>'} ${esc(last.date)}${bad.length && last.result === 'OK' ? ` · earlier failures: ${bad.length}` : ''}</div>`;
}
function renderTM() {
  const t = S.tm; if (!t) return; tmFill();
  const atlas = $('#tm-atlas').value, variant = $('#tm-variant').value;
  const sfx = tmSuffix() || '';      // results shown = outputs named <session><suffix>
  const checked = new Set($$('.tm-sel').filter(c => c.checked).map(c => c.dataset.sid));
  $('#tm-table thead').innerHTML = `<tr><th></th><th>Session${sfx ? ` <span class="muted" style="font-weight:normal">(results named &lt;session&gt;${esc(sfx)})</span>` : ''}</th><th>Input (${variant ? esc(variant) : 'none chosen'})</th><th>Frames kept (pipeline tmask)</th><th>rest / FD / tSNR</th><th>dconn</th>` +
    Object.keys(t.atlases).map(a => `<th>${esc(a)}</th>`).join('') + `<th>Job</th></tr>`;
  let ready = 0;
  const root = `${S.state.config.projects_root}/${S.project}`;
  $('#tm-table tbody').innerHTML = t.rows.map(r => {
    const ok = r.variants.includes(variant) && r.tmask; if (ok) ready++;
    const j = r.job && r.job.kind !== 'P2' ? r.job : null;
    const o = tmOut(r, sfx);
    // the output names this session has (plain id and/or suffixes); click one to show its results
    const names = Object.entries(r.outputs || {}).filter(([k, x]) => x.dconn || Object.keys(x.tm || {}).length || (x.status || []).length).map(([k]) => k);
    const namesHtml = names.length && !(names.length === 1 && names[0] === sfx) ? `<div class="muted" style="font-size:11px">outputs: ${names.map(k => k === sfx
        ? `<b>${k ? esc(k) : '(no suffix)'}</b>` : `<a href="#" data-sfx="${esc(k)}">${k ? esc(k) : '(no suffix)'}</a>`).join(' · ')}</div>` : '';
    return `<tr><td><input type="checkbox" class="tm-sel" data-sid="${esc(r.sid)}" ${ok ? '' : 'disabled'} ${checked.has(r.sid) ? 'checked' : ''}></td>
      <td><b>${esc(r.sid)}</b>${tmStatusHtml(o.status)}${namesHtml}</td><td>${!variant ? '<span class="muted">–</span>' : r.variants.includes(variant) ? '✓' : '<span class="err">missing</span>'}</td>
      <td>${r.total ? `${r.kept} / ${r.total} (${(100 * r.kept / r.total).toFixed(1)}%)` : '<span class="err">no tmask</span>'}</td>
      <td class="muted">${r.rest_frames ? 'rest' : '–'} / ${r.fd_file ? 'FD' : '–'} / ${r.tsnr ? 'tSNR' : '–'}</td><td>${o.dconn ? '✓' : '–'}</td>` +
      tmResultCells(o.tm, t.atlases, r.dir, '', o.name) + `<td>${j ? pill(j.state) + ' ' + esc(j.job_id) : ''}</td></tr>`; }).join('');
  $('#tm-counts').textContent = (variant ? `${t.rows.length} sessions, ${ready} with input for this variant`
    : `${t.rows.length} sessions - choose the input timeseries (left) to see which sessions have it`) + (sfx ? ` · results shown: <session>${sfx}` : '');
  tmSuffixNote();
  const csel = new Set($$('.tm-csel').filter(c => c.checked).map(c => c.dataset.name));
  $('#tm-concat tbody').innerHTML = t.concat.map(p => { const j = p.job;
    return `<tr><td><input type="checkbox" class="tm-csel" data-name="${esc(p.name)}" data-dir="${esc(p.dir)}" data-out="${esc(p.out_dir)}" ${csel.has(p.name) ? 'checked' : ''}></td>
      <td><b>${esc(p.name)}</b>${tmStatusHtml(p.status)}<div class="muted" style="font-size:11px">${esc(p.options)}</div></td>
      <td class="muted">${esc(p.sessions.join(', '))}<br><a href="#" data-txt="${esc(p.doc)}">sessions.txt</a></td>
      <td>${p.frames ? `${p.kept} / ${p.frames} (${(100 * p.kept / p.frames).toFixed(1)}%)` : '–'}${p.dconn ? '' : '<br><span class="err">no dconn</span>'}</td>
      <td><table class="inner"><tr>${tmResultCells(p.atlases, t.atlases, p.dir, p.out_dir, p.name)}</tr></table></td>
      <td>${j ? pill(j.state) + ' ' + esc(j.job_id) : ''}</td></tr>`; }).join('') ||
      '<tr><td colspan="6" class="muted">none yet — tick several sessions of one participant, choose "concatenate", submit. Tick a row here to rerun template matching / WTA on it.</td></tr>';
  $$('#tab-pfm a[data-sfx]').forEach(a => a.onclick = e => { e.preventDefault(); $('#tm-suffix').value = a.dataset.sfx; renderTM(); });
  $$('.tm-sel').forEach(c => c.addEventListener('change', tmSuffixNote));
  $$('#tab-pfm a[data-img]').forEach(a => a.onclick = e => { e.preventDefault(); modal('Cortical network map', `<p class="muted">${esc(a.dataset.img)}</p><img style="max-width:100%;background:#000" src="${fileUrl(a.dataset.img)}">`); });
  $$('#tab-pfm a[data-txt]').forEach(a => a.onclick = async e => { e.preventDefault(); try { const r = await fetch(fileUrl(a.dataset.txt)); modal(a.dataset.txt.split('/').pop(), `<pre class="result">${esc(await r.text())}</pre>`); } catch (err) { toast(err.message, true); } });
  $$('#tab-pfm a[data-csv]').forEach(a => a.onclick = async e => { e.preventDefault();
    try { const r = await api(`wta_table?csv=${encodeURIComponent(a.dataset.csv)}&atlas=${encodeURIComponent(a.dataset.atlas)}`);
      const fmt = v => isNaN(+v) ? esc(v) : (+v % 1 ? (+v).toFixed(1) : v);
      modal(`${a.dataset.name}: subcortical assignment by structure`, `<p class="muted">${esc(a.dataset.csv)}<br>Columns are the % of each structure's voxels assigned to each network; mean winner margin = how clearly the winning network won.</p>` +
        `<div class="tablewrap"><table class="compact"><thead><tr>${r.columns.map(c => `<th>${esc(c)}</th>`).join('')}</tr></thead><tbody>${r.rows.map(row => `<tr>${row.map((v, i) => `<td${i ? ' style="text-align:right"' : ''}>${fmt(v)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>` +
        (r.params ? `<details><summary>run parameters</summary><pre class="result">${esc(r.params)}</pre></details>` : '')); }
    catch (err) { toast(err.message, true); } });
}
$('#tm-sel-ready').onclick = () => $$('.tm-sel').forEach(c => c.checked = !c.disabled);
$('#tm-sel-none').onclick = () => $$('.tm-sel, .tm-csel').forEach(c => c.checked = false);
function tmBody(dry) {
  const steps = ['concat', 'tm', 'wta'].filter(s => $('#tm-step-' + s).checked);
  return {project: S.project, sids: $$('.tm-sel').filter(c => c.checked).map(c => c.dataset.sid), atlas: $('#tm-atlas').value,
    variant: $('#tm-variant').value, concat: tmMode() === 'concat', name: $('#tm-name').value.trim(), suffix: $('#tm-suffix').value.trim(), steps,
    analyses: $$('.tm-csel').filter(c => c.checked).map(c => c.dataset.name),
    rest_only: $('#tm-rest').checked, tsnr_mask: $('#tm-tsnrmask').checked, fd: $('#tm-fd').value, mem_limit: $('#tm-memlimit').value,
    wta_method: $('#tm-wta-method').value, top_pct: $('#tm-top').value, smooth: $('#tm-smooth').value, cleanup: $('#tm-cleanup').value,
    min_dist: $('#tm-mindist').value, no_norm: $('#tm-nonorm').checked,
    groups: $('#tm-groups').value, rerun: $('#tm-rerun').checked, dry_run: !!dry,
    notify_email: S.state.config.notify_email || '',
    slurm: {tm_partition: $('#tm-partition').value, tm_cpus: +$('#tm-cpus').value, tm_mem: $('#tm-mem').value, tm_time: $('#tm-time').value}};
}
$('#btn-tm-preview').onclick = async () => {
  if (tmSuffix() && !S.tm.suffix_supported) return toast('This GUI server predates the output name suffix: restart it (start_unp_gui.sh) first', true);
  try { const r = await api('submit_tm', tmBody(true)); modal('PFM job scripts (dry run)', r.scripts.map(x => `<h3>${esc(x.name)}</h3><pre class="result">${esc(x.text)}</pre>`).join('')); }
  catch (e) { modal('Cannot submit', `<pre class="result">${esc(e.message)}</pre>`); }
};
$('#btn-tm-submit').onclick = async () => {
  const b = tmBody(false);
  if (b.analyses.length && b.sids.length) return toast('Tick either sessions or concatenated analyses, not both', true);
  if (!b.sids.length && !b.analyses.length) return toast('Tick sessions (or a concatenated analysis) first', true);
  if (!b.steps.length) return toast('Tick at least one step', true);
  const sfx = tmSuffix();
  if (sfx === null) return toast('Invalid output name suffix: letters, digits, _ . - only, no _TM_', true);
  if (sfx && !S.tm.suffix_supported) return toast('This GUI server predates the output name suffix: restart it (start_unp_gui.sh) first', true);
  if (b.steps.includes('wta') && b.wta_method !== 'networkseed' && !S.tm.min_dist_supported) return toast('This GUI server predates the min-distance setting: restart it (start_unp_gui.sh) first', true);
  const sw = tmSuffixWarning(sfx, b.variant);
  const nameLine = b.analyses.length ? (sfx ? '\nOutput name suffix not used: existing concatenated analyses keep their names.' : '')
    : `\nOutputs named ${b.concat ? (b.name || '<Subject>_concat<N>') : '<session>'}${sfx}*` + (sw ? `\nWARNING: ${sw}.` : '');
  const nj = b.analyses.length || (b.concat ? new Set(b.sids.map(s => s.split('_')[0])).size : b.sids.length);
  if (!confirm(`Submit ${nj} PFM job(s): ${(b.analyses.length ? b.steps.filter(x => x !== 'concat') : b.steps).join(' → ')}${b.analyses.length ? ' on the existing concatenation (' + b.analyses.join(', ') + ')' : ''} (${b.atlas}, ${b.variant}${b.concat ? ', concatenated per participant' : ''}${b.rest_only ? ', rest frames only' : ''}${b.fd ? ', FD < ' + b.fd : ''}${b.steps.includes('wta') ? ', ' + b.wta_method + ' σ=' + (b.smooth || 0) + 'mm' + (b.no_norm && b.wta_method !== 'scoresmoothing_v3' ? ', no network normalization (nonorm)' : '') + (b.wta_method !== 'networkseed' ? ', min distance ' + (b.min_dist === '' ? 20 : b.min_dist) + 'mm' : '') : ''})?\nEach uses ${b.slurm.tm_mem} / ${b.slurm.tm_cpus} CPUs on ${b.slurm.tm_partition}.${nameLine}`)) return;
  try { const r = await api('submit_tm', b); const out = $('#tm-result'); out.classList.remove('hidden');
    out.innerHTML = r.submitted.map(j => `<span class="ok">submitted</span> ${esc(j.job_id)}  ${esc(j.name)}`).join('\n') + (r.errors.length ? '\n' + r.errors.map(e => `<span class="err">ERROR</span> ${esc(e)}`).join('\n') : '');
    loadTM(); }
  catch (e) { modal('Cannot submit', `<pre class="result">${esc(e.message)}</pre>`); }
};
$('#btn-tm-render-sub').onclick = async () => {
  const atlas = $('#tm-atlas').value;
  const sfx = tmSuffix() || '';
  const items = $$('.tm-sel').filter(c => c.checked).map(c => { const r = S.tm.rows.find(x => x.sid === c.dataset.sid); const o = r && tmOut(r, sfx);
      return o && o.tm[atlas] && o.tm[atlas].done ? {dir: r.dir, session: o.name, sid: r.sid, atlas} : null; }).filter(Boolean)
    .concat($$('.tm-csel').filter(c => c.checked).map(c => ({dir: c.dataset.dir, out_dir: c.dataset.out, session: c.dataset.name, atlas})));
  if (!items.length) return toast(`Tick sessions / concatenated analyses that have subcortical results for ${atlas}${sfx ? ' (outputs <session>' + sfx + ')' : ''}`, true);
  $('#btn-tm-render-sub').disabled = true; toast(`rendering subcortical images for ${items.length} row(s)…`);
  try { const r = await api('render_subcort', {project: S.project, items}); toast(`${r.rendered.length} image(s) rendered`, !r.ok);
    if (r.errors.length) modal('Some images failed', `<pre class="result">${esc(r.errors.join('\n'))}</pre>`); loadTM(); }
  catch (e) { toast(e.message, true); }
  $('#btn-tm-render-sub').disabled = false;
};
$('#btn-tm-render').onclick = async () => {
  const atlas = $('#tm-atlas').value;
  const sfx = tmSuffix() || '';
  const items = $$('.tm-sel').filter(c => c.checked).map(c => { const r = S.tm.rows.find(x => x.sid === c.dataset.sid); const o = r && tmOut(r, sfx);
      return o && o.tm[atlas] && o.tm[atlas].done ? {dir: r.dir, session: o.name, sid: r.sid, atlas} : null; }).filter(Boolean)
    .concat($$('.tm-csel').filter(c => c.checked).map(c => ({dir: c.dataset.dir, out_dir: c.dataset.out, session: c.dataset.name, atlas})));
  if (!items.length) return toast(`Tick sessions / concatenated analyses that have finished ${atlas} results${sfx ? ' (outputs <session>' + sfx + ')' : ''}`, true);
  $('#btn-tm-render').disabled = true; toast(`rendering ${items.length} map(s)… (~20 s each)`);
  try { const r = await api('render_tm', {project: S.project, items}); toast(`${r.rendered.length} map(s) rendered`, !r.ok);
    if (r.errors.length) modal('Some maps failed', `<pre class="result">${esc(r.errors.join('\n'))}</pre>`); loadTM(); }
  catch (e) { toast(e.message, true); }
  $('#btn-tm-render').disabled = false;
};

boot();
