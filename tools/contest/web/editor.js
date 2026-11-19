'use strict';
/* AhaSlides-style editor: slide list · live preview · settings. Saves to the room while in the lobby. */
(() => {
  const {h, $, put, api, toast, download, TYPE_NAMES, GRADED} = OES;
  const GALLERY = [
    ['Content', [['slide', 'Heading, text and an optional picture.']]],
    ['Quiz (scored)', [['choice', 'One correct option. Classic quiz question.'], ['multiple', 'Several correct options.'], ['text', 'Visitors type the answer; several spellings allowed.'],
      ['number', 'A numeric answer with a tolerance.'], ['order', 'Put items in the correct sequence.'], ['match', 'Match each item to its partner.'], ['category', 'Sort items into groups.']]],
    ['Opinion (not scored)', [['poll', 'Multiple-choice poll with live bars.'], ['cloud', 'Words grow as more people send them.'], ['scale', 'Rate from 1 to N.'],
      ['rank', 'Audience ranks the options; results by Borda score.'], ['open', 'Collect ideas and let people upvote them.']]],
    ['Interaction', [['qa', 'Show the audience Q&A board.'], ['spinner', 'Spin a wheel of names or entries.']]],
  ];
  const TEMPLATES = {
    slide: {type: 'slide', prompt: 'Welcome to the gallery', body: '- Scan the code on screen\n- Choose a nickname\n- Answer on your phone', layout: 'auto'},
    choice: {type: 'choice', prompt: 'Which planet is largest?', options: ['Earth', 'Jupiter', 'Mars', 'Venus'], answer: 'Jupiter', seconds: 30, points: 1000},
    multiple: {type: 'multiple', prompt: 'Which of these are metals?', options: ['Copper', 'Glass', 'Iron', 'Rubber'], answer: ['Copper', 'Iron'], seconds: 40, points: 1000},
    text: {type: 'text', prompt: 'What gas do plants take in for photosynthesis?', answer: ['carbon dioxide', 'CO2'], seconds: 40, points: 1000},
    number: {type: 'number', prompt: 'How many planets orbit the Sun?', answer: 8, tolerance: 0, seconds: 30, points: 1000},
    order: {type: 'order', prompt: 'Order these from smallest to largest', options: ['Atom', 'Cell', 'Molecule', 'Organism'], answer: ['Atom', 'Molecule', 'Cell', 'Organism'], seconds: 45, points: 1000},
    match: {type: 'match', prompt: 'Match each scientist to a discovery', labels: ['C. V. Raman', 'Marie Curie', 'Isaac Newton'], options: ['Gravitation', 'Light scattering', 'Radioactivity'], answer: ['Light scattering', 'Radioactivity', 'Gravitation'], seconds: 60, points: 1000},
    category: {type: 'category', prompt: 'Renewable or not?', labels: ['Solar', 'Coal', 'Wind', 'Diesel'], options: ['Renewable', 'Non-renewable'], answer: ['Renewable', 'Non-renewable', 'Renewable', 'Non-renewable'], seconds: 45, points: 1000},
    poll: {type: 'poll', prompt: 'Which gallery should we visit next?', options: ['Space', 'Energy', 'Life sciences'], seconds: 0, live_results: true},
    cloud: {type: 'cloud', prompt: 'One word that describes science for you', seconds: 0, live_results: true},
    scale: {type: 'scale', prompt: 'How much did you enjoy today?', scale_max: 5, low_label: 'Not much', high_label: 'Loved it', seconds: 0, live_results: true},
    rank: {type: 'rank', prompt: 'Rank these exhibits', options: ['Robots', 'Dinosaurs', 'Space'], seconds: 0, live_results: true},
    open: {type: 'open', prompt: 'What should our next exhibit be about?', max_entries: 3, moderate: false, seconds: 0, live_results: true},
    qa: {type: 'qa', prompt: 'Ask our scientist anything', seconds: 0},
    spinner: {type: 'spinner', prompt: 'Who answers the next question?', source: 'players', remove_winner: true, seconds: 0},
  };
  const clone = v => JSON.parse(JSON.stringify(v));
  const lines = t => t.split('\n').map(x => x.trim()).filter(Boolean);

  OES.editor = function editor() {
    document.body.className = 'edit';
    const root = $('#root');
    let deck = null, sel = 0, readOnly = false, dirty = false, saveTimer = 0, phase = 'lobby', joinUrl = '';
    const title = h('input', {type: 'text', maxlength: 120, 'aria-label': 'Session title', style: {maxWidth: '360px', fontFamily: 'var(--ui)'}});
    const status = h('span', {class: 'dim', id: 'e-status'});
    const importFile = h('input', {type: 'file', accept: '.json,.pptx,.pdf,.txt', hidden: true});
    const top = h('header', {class: 'topbar'}, h('span', {class: 'brand'}, h('i', {}, '◆ '), 'Slides'), title, status, h('span', {class: 'spacer'}),
      h('button', {class: 'btn', onclick: () => settings()}, '⚙ Session settings'),
      h('button', {class: 'btn', onclick: () => textImport()}, '⎘ Paste questions'),
      h('button', {class: 'btn', onclick: () => importFile.click()}, '⇧ Import file'), importFile,
      h('button', {class: 'btn', onclick: () => download(new Blob([JSON.stringify(deck, null, 2)], {type: 'application/json'}), (deck.title || 'slides').replace(/[^\w-]+/g, '-') + '.quiz.json')}, '⇩ Download'),
      h('button', {class: 'btn primary', id: 'e-save', onclick: () => save(true)}, 'Save ', h('kbd', {}, 'Ctrl S')),
      h('a', {class: 'btn blue', href: '/host'}, '▶ Present'));
    const banner = h('div', {class: 'banner', hidden: true});
    const list = h('div', {class: 'e-list'});
    const center = h('div', {class: 'e-center'});
    const preview = h('div', {class: 'h-preview'});
    const form = h('div', {class: 'e-form'});
    center.append(preview, h('p', {class: 'dim mono', style: {fontSize: '12px'}}, 'Preview of the projector screen. Results fill in live during the session.'));
    root.append(top, banner, h('div', {class: 'e-grid'}, list, center, form));
    const sv = OES.makeStage(preview);
    const gallery = h('dialog', {}, h('div', {class: 'd-head'}, h('b', {}, 'Add a slide'), h('span', {class: 'spacer'}), h('button', {class: 'btn icon', onclick: () => gallery.close()}, '✕')),
      h('div', {class: 'd-body'}, h('div', {class: 'gallery'}, GALLERY.map(([group, items]) => [h('h4', {}, group), items.map(([t, d]) => h('button', {onclick: () => { add(t); gallery.close(); }}, h('b', {}, TYPE_NAMES[t]), h('span', {}, d)))]))));
    root.append(gallery);

    title.addEventListener('input', () => { deck.title = title.value; changed(false); });
    document.addEventListener('keydown', e => { if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') { e.preventDefault(); save(true); } });
    window.addEventListener('beforeunload', e => { if (dirty && !readOnly) { e.preventDefault(); e.returnValue = ''; } });
    importFile.addEventListener('change', () => importFrom(importFile.files[0]).catch(toast).finally(() => { importFile.value = ''; }));

    api('/api/host/state').then(s => {
      deck = clone(s.deck); phase = s.phase; joinUrl = s.join_url;
      readOnly = s.phase !== 'lobby';
      if (readOnly) { banner.hidden = false; banner.textContent = 'This session has already started, so its slides are locked. Download them, then start a new session from Studio to edit.'; }
      title.value = deck.title; title.disabled = readOnly; $('#e-save').disabled = readOnly;
      drawList(); select(0);
    }).catch(e => { root.replaceChildren(h('div', {class: 'card', style: {margin: '60px auto', maxWidth: '560px'}}, h('h2', {}, 'Editor unavailable'), h('p', {}, e.message), h('p', {class: 'dim'}, 'Open the editor again from Studio → Live audience → Edit slides.'))); });

    function changed(redrawList = true) {
      dirty = true; status.textContent = 'Unsaved changes';
      if (redrawList) drawList();
      renderPreview();
      clearTimeout(saveTimer); if (!readOnly) saveTimer = setTimeout(() => save(false), 1200);
    }
    async function save(explicit) {
      if (readOnly || !deck) return;
      clearTimeout(saveTimer);
      try {
        const s = await api('/api/host/state');
        await api('/api/host/action', {action: 'deck', phase: s.phase, round: s.index, deck});
        dirty = false; status.textContent = 'Saved ✓'; if (explicit) toast('Slides saved to this session', true);
      } catch (e) { status.textContent = '⚠ ' + e.message; if (explicit) toast(e); }
    }

    function drawList() {
      put(list, ...deck.questions.map((q, i) => h('div', {class: 'e-item' + (i === sel ? ' on' : ''), 'data-i': i, onclick: () => select(i)},
        h('span', {class: 'num'}, i + 1), h('div', {class: 'what'}, h('b', {}, TYPE_NAMES[q.type]), h('span', {}, q.prompt)),
        readOnly ? null : h('div', {class: 'acts'}, h('button', {title: 'Duplicate', onclick: e => { e.stopPropagation(); deck.questions.splice(i + 1, 0, clone(q)); sel = i + 1; changed(); select(sel); }}, '⧉'),
          h('button', {title: 'Delete', onclick: e => { e.stopPropagation(); if (deck.questions.length < 2) return toast('A session needs at least one slide.'); if (!confirm('Delete slide ' + (i + 1) + '?')) return; deck.questions.splice(i, 1); sel = Math.min(sel, deck.questions.length - 1); changed(); select(sel); }}, '🗑')))),
      readOnly ? h('span') : h('button', {class: 'btn', style: {width: '100%', justifyContent: 'center', marginTop: '8px'}, onclick: () => gallery.showModal()}, '+ Add slide'));
      if (!readOnly && window.Sortable && !list._sortable) list._sortable = window.Sortable.create(list, {draggable: '.e-item', animation: 150, onEnd: ev => {
        if (ev.oldIndex === ev.newIndex) return;
        const [m] = deck.questions.splice(ev.oldIndex, 1); deck.questions.splice(ev.newIndex, 0, m); sel = ev.newIndex; changed(); select(sel);
      }});
    }
    function add(type) {
      const q = clone(TEMPLATES[type]);
      deck.questions.splice(sel + 1, 0, q); sel = sel + 1; changed(); select(sel);
    }
    function select(i) {
      sel = i; for (const el of list.querySelectorAll('.e-item')) el.classList.toggle('on', Number(el.dataset.i) === i);
      drawForm(); renderPreview();
    }
    function renderPreview() {
      const q = deck.questions[sel]; if (!q) return;
      const sample = {poll: (q.options || []).map((o, i) => [o, [12, 7, 4, 3, 2, 1][i % 6]]), rank: (q.options || []).map((o, i) => [o, 20 - 3 * i]), scale: [['3', 2], ['4', 5], ['5', 8]], cloud: [['curious', 9], ['energy', 6], ['stars', 5], ['atoms', 4], ['wonder', 3], ['light', 2]]};
      OES.renderStage(sv, {title: deck.title, code: '123456', phase: 'open', index: sel, rounds: deck.questions.length, question: q, distribution: sample[q.type] || [], answer: null,
        ideas: q.type === 'open' ? [{id: 1, body: 'A hands-on tsunami tank', votes: 7, status: 'shown'}, {id: 2, body: 'Build-your-own satellite', votes: 4, status: 'shown'}] : [],
        qa: [{id: 1, body: 'How do black holes form?', votes: 5, status: 'published'}], spinner: {entries: q.source === 'players' ? ['Asha', 'Bilal', 'Chen', 'Dev', 'Esha', 'Farah'] : (q.options || []), seq: 0},
        seconds_left: q.seconds, received: 0, players: 0, settings: {theme: deck.theme, leaderboard: deck.leaderboard}, join_host: joinUrl.replace(/^https?:\/\//, '').split('/')[0], graded_rounds: 1}, {preview: true});
    }

    // ----------------------------------------------------------------- form controls
    function field(label, control, hint) { return h('label', {class: 'field'}, label, control, hint ? h('span', {style: {fontSize: '12px'}}, hint) : null); }
    function text(q, key, label, {area = false, max = 500, hint = '', rows = 3} = {}) {
      const c = h(area ? 'textarea' : 'input', {type: 'text', maxlength: max, rows, value: q[key] || '', disabled: readOnly});
      if (area) c.value = q[key] || '';
      c.addEventListener('input', () => { if (c.value.trim()) q[key] = c.value; else delete q[key]; changed(key === 'prompt'); });
      return field(label, c, hint);
    }
    function num(q, key, label, min, max, hint) {
      const c = h('input', {type: 'number', min, max, step: key === 'tolerance' || key === 'answer' ? 'any' : 1, value: q[key] ?? '', disabled: readOnly});
      c.addEventListener('input', () => { if (c.value !== '') { q[key] = Number(c.value); changed(false); } });
      return field(label, c, hint);
    }
    function check(q, key, label, fallback = false) {
      const c = h('input', {type: 'checkbox', checked: q[key] ?? fallback, disabled: readOnly});
      c.addEventListener('change', () => { q[key] = c.checked; changed(false); });
      return h('label', {class: 'check'}, c, label);
    }
    function choose(q, key, label, opts) {
      const c = h('select', {disabled: readOnly}, opts.map(([v, t]) => h('option', {value: v, selected: q[key] === v}, t)));
      c.addEventListener('change', () => { q[key] = c.value; changed(false); drawForm(); });
      return field(label, c);
    }
    /** Editable list of options. mark: 'radio' | 'check' | null decides how correct answers are chosen. */
    function optionList(q, label, mark, {key = 'options', max = 12, min = 2} = {}) {
      const box = h('div');
      const items = q[key] || (q[key] = []);
      const draw = () => put(box, h('div', {class: 'h-status', style: {marginBottom: '6px'}}, label), ...items.map((o, i) => {
        const input = h('input', {type: 'text', maxlength: key === 'options' && q.type === 'spinner' ? 60 : 120, value: o, disabled: readOnly, 'aria-label': label + ' ' + (i + 1)});
        input.addEventListener('input', () => {
          const old = items[i]; items[i] = input.value;
          if (mark === 'radio' && q.answer === old) q.answer = input.value;
          if (mark === 'check' && Array.isArray(q.answer)) q.answer = q.answer.map(a => a === old ? input.value : a);
          changed(false);
        });
        let marker = null;
        if (mark === 'radio') { marker = h('input', {type: 'radio', name: 'correct', checked: q.answer === o, disabled: readOnly, title: 'Correct answer'}); marker.addEventListener('change', () => { q.answer = items[i]; changed(false); }); }
        if (mark === 'check') { marker = h('input', {type: 'checkbox', checked: (q.answer || []).includes(o), disabled: readOnly, title: 'Correct'}); marker.addEventListener('change', () => { const s = new Set(q.answer || []); marker.checked ? s.add(items[i]) : s.delete(items[i]); q.answer = items.filter(x => s.has(x)); changed(false); }); }
        return h('div', {class: 'optrow'}, marker, input, readOnly ? null : h('button', {class: 'x', title: 'Remove', onclick: () => { if (items.length <= min) return toast('Keep at least ' + min + '.'); const [gone] = items.splice(i, 1); if (q.answer === gone) q.answer = items[0]; if (Array.isArray(q.answer)) q.answer = q.answer.filter(a => a !== gone); changed(false); draw(); }}, '✕'));
      }), readOnly || items.length >= max ? null : h('button', {class: 'btn icon', onclick: () => { items.push('Option ' + (items.length + 1)); changed(false); draw(); }}, '+ Add'));
      draw();
      return box;
    }
    function imagePicker(q) {
      const file = h('input', {type: 'file', accept: 'image/png,image/jpeg,image/webp', disabled: readOnly});
      file.addEventListener('change', async () => {
        const f = file.files[0]; if (!f) return;
        try { q.image = await shrink(f); changed(false); drawForm(); } catch (e) { toast(e); }
      });
      return h('div', {class: 'stack'}, field('Picture (resized automatically)', file), q.image ? h('div', {class: 'row'}, h('img', {src: q.image, style: {maxHeight: '80px', borderRadius: '6px'}}), readOnly ? null : h('button', {class: 'btn icon', onclick: () => { delete q.image; changed(false); drawForm(); }}, 'Remove')) : null);
    }
    async function shrink(f) {
      const url = URL.createObjectURL(f);
      try {
        const img = await new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => no(new Error('That picture could not be read.')); i.src = url; });
        for (const [side, quality] of [[1600, .85], [1280, .8], [1024, .75], [800, .7]]) {
          const k = Math.min(1, side / Math.max(img.width, img.height));
          const c = h('canvas', {width: Math.round(img.width * k), height: Math.round(img.height * k)});
          c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
          const data = c.toDataURL('image/jpeg', quality);
          if (data.length * 0.75 < 500000) return data;
        }
        throw new Error('That picture is too detailed to fit. Try a smaller image.');
      } finally { URL.revokeObjectURL(url); }
    }
    function timing(q) {
      const graded = GRADED.has(q.type);
      if (graded) return num(q, 'seconds', 'Time limit (seconds)', 3, 600);
      const on = h('input', {type: 'checkbox', checked: q.seconds > 0, disabled: readOnly});
      const secs = h('input', {type: 'number', min: 3, max: 600, value: q.seconds || 60, disabled: readOnly || !(q.seconds > 0), style: {maxWidth: '110px'}});
      on.addEventListener('change', () => { q.seconds = on.checked ? Number(secs.value) || 60 : 0; secs.disabled = !on.checked; changed(false); });
      secs.addEventListener('input', () => { if (on.checked) { q.seconds = Number(secs.value); changed(false); } });
      return h('div', {class: 'row'}, h('label', {class: 'check'}, on, 'Time limit'), secs, h('span', {class: 'dim', style: {fontSize: '12px'}}, 'Off = open until you move on'));
    }

    function drawForm() {
      const q = deck.questions[sel]; if (!q) return put(form, );
      const type = h('select', {disabled: readOnly}, Object.keys(TEMPLATES).map(t => h('option', {value: t, selected: t === q.type}, TYPE_NAMES[t])));
      type.addEventListener('change', () => {
        const fresh = clone(TEMPLATES[type.value]); fresh.prompt = q.prompt;
        if (q.options && fresh.options && !['match', 'category', 'order'].includes(type.value)) { fresh.options = q.options.slice(); if (type.value === 'choice') fresh.answer = fresh.options[0]; if (type.value === 'multiple') fresh.answer = [fresh.options[0]]; }
        deck.questions[sel] = fresh; changed(); drawForm();
      });
      const parts = [h('h3', {}, 'Slide ' + (sel + 1)), field('Slide type', type), text(q, 'prompt', q.type === 'slide' ? 'Heading' : 'Question', {area: true, max: 500, rows: 2})];
      const t = q.type;
      if (t === 'slide') parts.push(text(q, 'body', 'Text — start lines with “- ” for bullets', {area: true, max: 1500, rows: 6}),
        choose(q, 'layout', 'Layout', [['auto', 'Automatic'], ['title', 'Title slide'], ['big', 'Big statement'], ['image-right', 'Text left, picture right'], ['image-left', 'Picture left, text right']]));
      if (t === 'choice') parts.push(optionList(q, 'Options — select the correct one', 'radio'));
      if (t === 'multiple') parts.push(optionList(q, 'Options — tick every correct one', 'check'));
      if (t === 'poll' || t === 'rank') parts.push(optionList(q, 'Options', null));
      if (t === 'order') {
        const items = q.answer.slice();
        const box = h('textarea', {rows: 5, disabled: readOnly}); box.value = items.join('\n');
        box.addEventListener('input', () => { const v = lines(box.value); if (v.length >= 2 && new Set(v).size === v.length) { q.answer = v; q.options = shuffled(v); changed(false); } });
        parts.push(field('Items in the CORRECT order — one per line', box, 'Phones show them shuffled.'));
      }
      if (t === 'text') { const box = h('textarea', {rows: 3, disabled: readOnly}); box.value = (q.answer || []).join('\n'); box.addEventListener('input', () => { const v = lines(box.value); if (v.length) { q.answer = v; changed(false); } }); parts.push(field('Accepted answers — one per line', box, 'Case, accents of letters and extra spaces are ignored.')); }
      if (t === 'number') parts.push(num(q, 'answer', 'Correct number', -1e12, 1e12), num(q, 'tolerance', 'Accept answers within ±', 0, 1e12));
      if (t === 'match') parts.push(pairs(q));
      if (t === 'category') parts.push(categories(q));
      if (t === 'scale') parts.push(num(q, 'scale_max', 'Highest rating', 2, 10), text(q, 'low_label', 'Label for 1', {max: 40}), text(q, 'high_label', 'Label for the top rating', {max: 40}));
      if (t === 'open') parts.push(num(q, 'max_entries', 'Ideas per person', 1, 10), check(q, 'moderate', 'Approve ideas before they appear'));
      if (t === 'spinner') {
        parts.push(choose(q, 'source', 'Wheel entries', [['players', 'Everyone who joined'], ['entries', 'My own list']]));
        if (q.source === 'entries') { if (!q.options || q.options.length < 2) q.options = ['Prize 1', 'Prize 2', 'Prize 3']; parts.push(optionList(q, 'Entries', null, {max: 40})); }
        parts.push(check(q, 'remove_winner', 'Remove each winner from the wheel'));
      }
      if (['poll', 'scale', 'cloud', 'rank', 'open'].includes(t)) parts.push(check(q, 'live_results', 'Show results live as they arrive', true));
      if (t !== 'slide') parts.push(timing(q));
      if (GRADED.has(t)) parts.push(num(q, 'points', 'Points for a correct answer', 0, 10000), text(q, 'explanation', 'Explanation shown after the answer', {area: true, max: 600, rows: 2}));
      parts.push(imagePicker(q), text(q, 'notes', 'Presenter notes (only you see these)', {area: true, max: 2000, rows: 3}));
      put(form, ...parts);
    }
    function shuffled(v) {
      const out = v.slice(); for (let i = out.length - 1; i > 0; i--) { const j = (i * 7 + 3) % (i + 1); [out[i], out[j]] = [out[j], out[i]]; }
      if (out.join('\u0000') === v.join('\u0000')) [out[0], out[1]] = [out[1], out[0]];
      return out;
    }
    function pairs(q) {
      const box = h('textarea', {rows: 5, disabled: readOnly});
      box.value = q.labels.map((l, i) => l + ' = ' + q.answer[i]).join('\n');
      box.addEventListener('input', () => {
        const rows = lines(box.value).map(l => l.split('=').map(x => x.trim())).filter(r => r.length === 2 && r[0] && r[1]);
        if (rows.length >= 2 && new Set(rows.map(r => r[1])).size === rows.length) { q.labels = rows.map(r => r[0]); q.answer = rows.map(r => r[1]); q.options = shuffled(q.answer); changed(false); }
      });
      return field('Pairs — one per line as  item = match', box, 'Each match must be different.');
    }
    function categories(q) {
      const cats = h('input', {type: 'text', value: q.options.join(', '), disabled: readOnly});
      const items = h('textarea', {rows: 5, disabled: readOnly});
      items.value = q.labels.map((l, i) => l + ' = ' + q.answer[i]).join('\n');
      const apply = () => {
        const groups = cats.value.split(',').map(x => x.trim()).filter(Boolean);
        const rows = lines(items.value).map(l => l.split('=').map(x => x.trim())).filter(r => r.length === 2 && groups.includes(r[1]));
        if (groups.length >= 2 && rows.length >= 2) { q.options = groups; q.labels = rows.map(r => r[0]); q.answer = rows.map(r => r[1]); changed(false); }
      };
      cats.addEventListener('input', apply); items.addEventListener('input', apply);
      return h('div', {class: 'stack'}, field('Groups — separated by commas', cats), field('Items — one per line as  item = group', items));
    }

    // ----------------------------------------------------------------- dialogs
    function modal(titleText, body, actions) {
      const d = h('dialog');
      d.append(h('div', {class: 'd-head'}, h('b', {}, titleText), h('span', {class: 'spacer'}), h('button', {class: 'btn icon', onclick: () => d.close()}, '✕')),
        h('div', {class: 'd-body stack'}, body, h('div', {class: 'row'}, h('span', {class: 'spacer'}), actions(d))));
      d.addEventListener('close', () => d.remove()); document.body.append(d); d.showModal(); return d;
    }
    function settings() {
      const s = clone(deck);
      const teams = h('textarea', {rows: 3}); teams.value = (s.teams || []).join('\n');
      const box = h('div', {class: 'stack'},
        field('Teams — one per line (leave empty for individual play)', teams, 'Teams cannot change once people have joined.'),
        choose(s, 'leaderboard', 'Leaderboard', [['each', 'After every quiz question'], ['end', 'Only at the end'], ['never', 'Never (results only)']]),
        choose(s, 'theme', 'Projector theme', [['dark', 'Dark (GitHub dark)'], ['light', 'Light — better in bright rooms']]),
        check(s, 'speed_bonus', 'Faster correct answers score more (down to half points)', true),
        check(s, 'anonymous', 'Let people join without a name'),
        check(s, 'reactions', 'Allow emoji reactions', true),
        check(s, 'qa', 'Allow audience questions (Q&A)', true));
      box.querySelectorAll('select,input').forEach(c => { c.disabled = readOnly; });
      modal('Session settings', box, d => [h('button', {class: 'btn primary', disabled: readOnly, onclick: () => {
        for (const k of ['leaderboard', 'theme', 'speed_bonus', 'anonymous', 'reactions', 'qa']) deck[k] = s[k];
        deck.teams = lines(teams.value); changed(false); d.close(); }}, 'Apply')]);
    }
    function textImport() {
      const t = h('textarea', {rows: 14, placeholder: 'What is the chemical symbol for gold?\nA. Ag\nB. Au\nANSWER: B\n\nWhich gallery should open next?\nA. Robots\nB. Oceans'});
      modal('Paste questions (Aiken format)', h('div', {class: 'stack'}, h('p', {class: 'dim'}, 'One question per block, blank line between blocks. Options start with A. B. C. … Add “ANSWER: B” for a quiz question (“ANSWER: A, C” for several). Without an ANSWER line the block becomes a poll; plain lines become a content slide. Moodle Aiken files work as they are.'), t),
        d => [h('button', {class: 'btn', onclick: () => run(d, false)}, 'Replace all slides'), h('button', {class: 'btn primary', onclick: () => run(d, true)}, 'Add to my slides')]);
      async function run(d, append) {
        try {
          const got = await api('/api/host/text', {text: t.value, title: deck.title});
          if (append) deck.questions.push(...got.questions); else { if (!confirm('Replace all ' + deck.questions.length + ' slides?')) return; deck.questions = got.questions; }
          d.close(); sel = append ? deck.questions.length - got.questions.length : 0; changed(); select(sel); toast(got.questions.length + ' slides imported', true);
        } catch (e) { toast(e); }
      }
    }
    async function importFrom(file) {
      if (!file) return;
      if (file.size > 8 * 1024 * 1024) throw new Error('Choose a file smaller than 8 MiB.');
      let got;
      if (/\.json$/i.test(file.name)) got = JSON.parse(await file.text());
      else {
        const data = await new Promise((ok, no) => { const r = new FileReader(); r.onload = () => ok(String(r.result).split(',')[1]); r.onerror = () => no(new Error('File could not be read.')); r.readAsDataURL(file); });
        status.textContent = 'Importing…';
        got = await api('/api/host/import', {file: data, name: file.name});
      }
      if (got.format !== 'oes-quiz' || !Array.isArray(got.questions) || !got.questions.length) throw new Error('That file does not contain slides.');
      const append = confirm('Add ' + got.questions.length + ' imported slides after your current slides?\n\nOK = add · Cancel = replace everything');
      if (append) deck.questions.push(...got.questions);
      else { const keepTeams = deck.teams; deck = Object.assign(got, {teams: got.teams && got.teams.length ? got.teams : keepTeams}); title.value = deck.title; }
      sel = 0; changed(); select(sel); toast('Imported ' + got.questions.length + ' slides', true);
    }
  };
})();
