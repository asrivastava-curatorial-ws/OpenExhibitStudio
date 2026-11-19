'use strict';
/* OpenExhibit live audience — core helpers and the participant (phone) view.
   present.js adds the projector and presenter views; editor.js adds the slide editor. */
const OES = (window.OES = {});
(() => {
  const mode = {'/host': 'host', '/display': 'display', '/edit': 'edit'}[location.pathname] || 'player';
  const operator = mode === 'host' || mode === 'edit';
  const key = 'oes-live-' + (operator ? 'host' : 'player') + '-' + location.host;
  const store = operator ? sessionStorage : localStorage;
  let token = store.getItem(key) || '';
  if (operator && location.hash.length > 1) {
    token = location.hash.slice(1);
    store.setItem(key, token);
    history.replaceState(null, '', location.pathname);
  }
  const $ = (sel, el = document) => el.querySelector(sel);

  /** Tiny element builder: h('button', {class: 'btn', onclick: fn}, 'Label', child…) */
  function h(tag, props, ...kids) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(props || {})) {
      if (v === undefined || v === null || v === false) continue;
      if (k === 'class') el.className = v;
      else if (k === 'text') el.textContent = v;
      else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
      else if (k.startsWith('on') && typeof v === 'function')
        el.addEventListener(k.slice(2), e => {
          try {
            const r = v(e);
            if (r && r.catch) r.catch(toast);
          } catch (err) {
            toast(err);
          }
        });
      else if (k in el && typeof v !== 'string') el[k] = v;
      else el.setAttribute(k, v === true ? '' : v);
    }
    for (const kid of kids.flat(Infinity))
      if (kid !== null && kid !== undefined && kid !== false)
        el.append(kid instanceof Node ? kid : String(kid));
    return el;
  }
  let toastTimer = 0;
  function toast(err, ok = false) {
    const t = $('#toast');
    t.textContent = err && err.message ? err.message : String(err);
    t.className = 'toast' + (ok ? ' ok' : '');
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(
      () => {
        t.hidden = true;
      },
      ok ? 2500 : 5000,
    );
  }
  async function api(path, body, raw = false, signal = null) {
    const headers = {};
    if (token) headers.Authorization = 'Bearer ' + token;
    const opts = {headers, cache: 'no-store'};
    if (body !== undefined) {
      headers['Content-Type'] = 'application/json';
      opts.method = 'POST';
      opts.body = JSON.stringify(body);
    }
    if (signal) opts.signal = signal;
    const r = await fetch(path, opts);
    if (raw) {
      if (!r.ok) throw new Error('Request failed (' + r.status + ')');
      return r;
    }
    let d;
    try {
      d = await r.json();
    } catch (e) {
      // an aborted long-poll must stay an AbortError, never become a fake state
      if (e.name === 'AbortError') throw e;
      const err = new Error('Unexpected reply from the session service.');
      err.status = r.status;
      throw err;
    }
    if (!r.ok) {
      const e = new Error(d.error || 'Request failed');
      e.status = r.status;
      throw e;
    }
    return d;
  }
  /** replaceChildren that accepts nested arrays and skips null/false (used for every re-render). */
  const put = (el, ...kids) =>
    el.replaceChildren(...kids.flat(Infinity).filter(k => k !== null && k !== undefined && k !== false));
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  /** Long-poll loop: the server answers as soon as anything changes (or after ~20 s). */
  function live(path, onState, {withPulse = false} = {}) {
    let version = 0,
      pulse = null,
      ctl = null,
      stopped = false,
      delay = 600;
    const setDot = on => {
      const d = $('#dot');
      if (d) d.className = 'dot' + (on ? ' on' : '');
      const c = $('#conn');
      if (c) c.textContent = on ? '' : 'Reconnecting…';
    };
    (async () => {
      while (!stopped) {
        try {
          ctl = new AbortController();
          const q = version
            ? '?since=' + version + (withPulse && pulse !== null ? '&pulse=' + pulse : '')
            : '';
          const s = await api(path + q, undefined, false, ctl.signal);
          version = s.version;
          pulse = s.pulse;
          delay = 600;
          setDot(true);
          onState(s);
        } catch (e) {
          if (e.name === 'AbortError') {
            version = 0;
            continue;
          }
          if (e.status === 403 && !operator && token) {
            token = '';
            localStorage.removeItem(key);
            version = 0;
            continue;
          }
          if (e.status === 403 && operator) {
            stopped = true;
            onState(null, e);
            return;
          }
          setDot(false);
          await sleep(delay);
          delay = Math.min(delay * 1.6, 5000);
          version = 0;
        }
      }
    })();
    return {
      refresh() {
        if (ctl) ctl.abort();
      },
      stop() {
        stopped = true;
        if (ctl) ctl.abort();
      },
    };
  }
  function loadScript(src) {
    return new Promise((ok, no) => {
      const s = h('script', {src});
      s.onload = ok;
      s.onerror = () => no(new Error('Could not load ' + src));
      document.head.append(s);
    });
  }
  function download(blob, name) {
    const a = h('a', {href: URL.createObjectURL(blob), download: name});
    document.body.append(a);
    a.click();
    setTimeout(() => {
      URL.revokeObjectURL(a.href);
      a.remove();
    }, 3000);
  }
  const TYPE_NAMES = {
    slide: 'Content',
    choice: 'Pick one',
    multiple: 'Pick several',
    text: 'Type an answer',
    number: 'Numeric answer',
    order: 'Correct order',
    match: 'Match pairs',
    category: 'Categorise',
    poll: 'Poll',
    scale: 'Rating scale',
    cloud: 'Word cloud',
    rank: 'Ranking',
    open: 'Open-ended',
    qa: 'Q&A',
    spinner: 'Spinner wheel',
  };
  const GRADED = new Set(['choice', 'multiple', 'text', 'number', 'order', 'match', 'category']);
  const REACTIONS = ['👍', '❤️', '😂', '😮', '👏', '🤔'];
  const answerText = (q, a) =>
    Array.isArray(a)
      ? a.map((x, i) => (q.labels ? q.labels[i] + ' → ' + x : x)).join(q.type === 'order' ? '  →  ' : ' · ')
      : String(a);
  Object.assign(OES, {
    mode,
    h,
    $,
    put,
    api,
    live,
    toast,
    sleep,
    loadScript,
    download,
    TYPE_NAMES,
    GRADED,
    REACTIONS,
    answerText,
    get token() {
      return token;
    },
  });

  // ======================================================================== participant
  function player() {
    document.body.className = 'player';
    const root = $('#root');
    const main = h('main', {class: 'p-main', id: 'p-main'});
    const extra = h('section', {id: 'p-extra'});
    root.append(
      h(
        'header',
        {class: 'p-head'},
        h('span', {class: 'dot', id: 'dot'}),
        h('b', {id: 'p-title'}, 'Live session'),
        h('span', {class: 'spacer'}),
        h('span', {class: 'dim', id: 'p-me'}),
      ),
      main,
      h('div', {class: 'p-main', style: {paddingTop: 0}}, extra),
    );
    const bar = h('nav', {class: 'reactbar', hidden: true});
    const qaDialog = h(
      'dialog',
      {},
      h(
        'div',
        {class: 'd-head'},
        h('b', {}, 'Ask the presenter'),
        h('span', {class: 'spacer'}),
        h('button', {class: 'btn icon', onclick: () => qaDialog.close()}, '✕'),
      ),
      h('div', {class: 'd-body', id: 'qa-body'}),
    );
    root.append(bar, qaDialog);
    let state = null,
      sig = '',
      extraSig = '',
      qaSig = '',
      deadline = 0,
      total = 1,
      busy = false,
      refreshedAt = -1;
    const loop = live('/api/state', s => {
      state = s;
      render(s);
    });

    function send(path, body) {
      if (busy) return Promise.resolve();
      busy = true;
      return api(path, body)
        .then(() => loop.refresh())
        .catch(toast)
        .finally(() => {
          busy = false;
        });
    }
    function timerBar() {
      const t = h('div', {class: 'p-timer', id: 'p-timer'}, h('i'));
      return t;
    }
    setInterval(() => {
      const t = $('#p-timer');
      if (!t || !state) return;
      const left = Math.max(0, (deadline - performance.now()) / 1000);
      t.firstChild.style.width = (100 * left) / total + '%';
      t.className = 'p-timer' + (left < 5 ? ' low' : '');
      if (left <= 0 && state.self_paced && state.phase === 'open' && refreshedAt !== deadline) {
        refreshedAt = deadline;
        loop.refresh();
      }
    }, 200);

    function joinForm(s) {
      const params = new URLSearchParams(location.search);
      const code = h('input', {
        type: 'text',
        inputmode: 'numeric',
        maxlength: 6,
        value: params.get('room') || '',
        autocomplete: 'off',
        'aria-label': 'Room code',
      });
      const name = h('input', {
        type: 'text',
        maxlength: 32,
        autocomplete: 'nickname',
        'aria-label': 'Display name',
        placeholder:
          s.settings && s.settings.anonymous
            ? 'Optional — leave empty to stay anonymous'
            : 'Your name or nickname',
      });
      const team = h(
        'select',
        {'aria-label': 'Team'},
        s.teams.map(t => h('option', {value: t}, t)),
      );
      const prefilled = (params.get('room') || '') === s.code;
      const form = h(
        'form',
        {
          class: 'stack',
          onsubmit: async e => {
            e.preventDefault();
            const r = await api('/api/join', {code: code.value.trim(), name: name.value, team: team.value});
            token = r.token;
            localStorage.setItem(key, token);
            sig = '';
            loop.refresh();
          },
        },
        prefilled
          ? h('p', {class: 'dim mono'}, 'Room ' + s.code)
          : h('label', {class: 'field'}, 'Room code', code),
        h('label', {class: 'field'}, 'Display name', name),
        s.teams.length ? h('label', {class: 'field'}, 'Team', team) : null,
        h('button', {class: 'btn primary big', type: 'submit'}, 'Join'),
      );
      put(
        main,
        h('h2', {}, s.title),
        h('p', {class: 'dim'}, 'No app or account needed. Your answers stay on this local network.'),
        form,
      );
      setTimeout(() => name.focus(), 50);
    }

    function render(s) {
      if (!s || typeof s.code !== 'string') return;
      $('#p-title').textContent = s.title;
      document.body.classList.toggle('light', !!(s.settings && s.settings.theme === 'light'));
      const joined = !!s.me;
      $('#p-me').textContent = joined ? s.me.name + (s.me.team ? ' · ' + s.me.team : '') : '';
      if (!joined) {
        bar.hidden = true;
        put(extra);
        if (s.phase === 'finished') {
          put(
            main,
            h('div', {class: 'done'}, h('div', {class: 'big'}, '👋'), h('h2', {}, 'This session has ended')),
          );
          return;
        }
        if (sig !== 'join:' + s.code) {
          sig = 'join:' + s.code;
          joinForm(s);
        }
        return;
      }
      renderBar(s);
      const q = s.question;
      if (s.phase === 'open') {
        deadline = performance.now() + s.seconds_left * 1000;
        total = q ? q.seconds : 1;
      }
      const nextSig = JSON.stringify([
        s.code,
        s.index,
        s.phase,
        s.session_phase,
        q && q.prompt,
        s.me.submitted,
        s.me.points,
        s.answer,
        s.leaders && s.leaders.slice(0, 5),
        s.me.rank,
        s.total_score,
        q && q.type === 'open' && s.me.ideas,
        s.spinner && s.spinner.seq,
        q && q.type === 'spinner' && s.spinner && s.spinner.entries.length,
        q && !GRADED.has(q.type) && (s.me.submitted || s.phase !== 'open') ? s.distribution : null,
      ]);
      if (nextSig !== sig) {
        sig = nextSig;
        renderMain(s);
      }
      const eSig = JSON.stringify([s.index, s.phase, s.ideas, s.me.voted, q && q.type === 'qa' && s.qa]);
      if (eSig !== extraSig) {
        extraSig = eSig;
        renderExtra(s);
      }
      const qSig = JSON.stringify(s.qa);
      if (qSig !== qaSig) {
        qaSig = qSig;
        renderQA(s);
      }
    }

    function renderBar(s) {
      const want = s.phase !== 'finished';
      bar.hidden = !want;
      if (!want || bar.childElementCount) return;
      if (!s.settings || s.settings.reactions !== false)
        for (const e of REACTIONS)
          bar.append(
            h(
              'button',
              {'aria-label': 'React ' + e, onclick: () => api('/api/react', {emoji: e}).catch(toast)},
              e,
            ),
          );
      if (!s.settings || s.settings.qa !== false)
        bar.append(
          h(
            'button',
            {
              class: 'ask',
              onclick: () => {
                renderQA(state);
                qaDialog.showModal();
              },
            },
            '? Ask',
          ),
        );
    }

    function renderQA(s) {
      const body = $('#qa-body');
      if (!s) return;
      const input = h('input', {
        type: 'text',
        maxlength: 240,
        placeholder: 'Type your question',
        'aria-label': 'Your question',
      });
      put(
        body,
        h(
          'form',
          {
            class: 'row',
            onsubmit: async e => {
              e.preventDefault();
              if (!input.value.trim()) return;
              await api('/api/ask', {text: input.value});
              input.value = '';
              toast('Sent to the presenter for review', true);
            },
          },
          input,
          h('button', {class: 'btn primary', type: 'submit'}, 'Send'),
        ),
        h(
          'p',
          {class: 'dim', style: {marginTop: '12px'}},
          'Questions appear here after the presenter approves them. Upvote the ones you want answered.',
        ),
        (s.qa || []).map(q =>
          h(
            'div',
            {class: 'idea'},
            h('p', {}, q.body),
            q.status === 'answered'
              ? h('span', {class: 'tag'}, 'answered')
              : h('button', {class: 'vote', onclick: () => send('/api/vote', {id: q.id})}, '▲ ' + q.votes),
          ),
        ),
      );
    }

    function verdict(s, q) {
      if (!GRADED.has(q.type)) return null;
      if (!s.me.submitted)
        return h(
          'div',
          {class: 'verdict wrong'},
          h('b', {}, 'No answer this time'),
          h('div', {}, 'Correct: ' + answerText(q, s.answer)),
        );
      const right = s.me.points > 0;
      return h(
        'div',
        {class: 'verdict ' + (right ? 'right' : 'wrong')},
        h('h2', {}, right ? '✓ Correct!  +' + s.me.points : '✗ Not quite'),
        right ? null : h('div', {}, 'Correct answer: ' + answerText(q, s.answer)),
        s.me.total !== undefined
          ? h(
              'div',
              {class: 'dim'},
              'Total ' + s.me.total + ' pts' + (s.me.rank ? ' · rank #' + s.me.rank : ''),
            )
          : null,
      );
    }

    function results(s, q) {
      const d = s.distribution || [];
      if (!d.length) return null;
      const max = Math.max(1, ...d.map(x => x[1]));
      return h(
        'div',
        {class: 'stack', style: {marginTop: '14px'}},
        d
          .slice(0, 12)
          .map(([label, n], i) =>
            h(
              'div',
              {},
              h(
                'div',
                {class: 'row'},
                h('span', {}, q.type === 'scale' ? '★ ' + label : label),
                h('span', {class: 'spacer'}),
                h('b', {class: 'mono'}, n),
              ),
              h(
                'div',
                {class: 'p-timer', style: {margin: '4px 0 0'}},
                h('i', {style: {width: (100 * n) / max + '%', background: 'var(--blue)'}}),
              ),
            ),
          ),
      );
    }

    function renderMain(s) {
      const q = s.question;
      const practice = s.self_paced && s.session_phase === 'practice';
      const advance = () => send('/api/practice/next', {round: s.index});
      if (practice && s.phase === 'lobby')
        return put(
          main,
          h(
            'div',
            {class: 'done'},
            h('div', {class: 'big'}, '🚀'),
            h('h2', {}, 'Ready?'),
            h('p', {class: 'dim'}, 'Go through the questions at your own pace.'),
            h('button', {class: 'btn primary big', onclick: advance}, 'Begin'),
          ),
        );
      if (practice && s.phase === 'finished')
        return put(
          main,
          h(
            'div',
            {class: 'done'},
            h('div', {class: 'big'}, '🏁'),
            h('h2', {}, 'You finished!'),
            h('p', {}, 'Your total: ' + s.total_score + ' points.'),
            h('p', {class: 'dim'}, 'Final standings appear when the presenter closes the session.'),
          ),
        );
      if (s.phase === 'lobby' || s.phase === 'practice')
        return put(
          main,
          h(
            'div',
            {class: 'done'},
            h('div', {class: 'big'}, '✅'),
            h('h2', {}, 'You’re in, ' + s.me.name + '!'),
            h('p', {class: 'dim'}, 'Watch the big screen. Questions will appear here.'),
          ),
        );
      if (s.phase === 'finished') {
        const graded = s.graded_rounds > 0;
        return put(
          main,
          h(
            'div',
            {class: 'done'},
            h('div', {class: 'big'}, graded && s.me.rank === 1 ? '🏆' : '🎉'),
            h('h2', {}, graded ? 'Final rank #' + (s.me.rank || '–') : 'Thanks for taking part!'),
            graded ? h('p', {}, (s.me.total || 0) + ' points') : null,
          ),
        );
      }
      if (s.phase === 'standings')
        return put(
          main,
          h(
            'div',
            {class: 'done'},
            h('div', {class: 'big'}, '📊'),
            h('h2', {}, 'You are #' + (s.me.rank || '–')),
            h('p', {}, (s.me.total || 0) + ' points so far'),
            h(
              'div',
              {class: 'stack', style: {textAlign: 'left', marginTop: '16px'}},
              (s.leaders || [])
                .slice(0, 5)
                .map(r =>
                  h(
                    'div',
                    {class: 'row idea'},
                    h('b', {class: 'mono'}, '#' + r.rank),
                    h('span', {}, r.name),
                    h('span', {class: 'spacer'}),
                    h('b', {class: 'mono'}, r.score),
                  ),
                ),
            ),
          ),
        );
      const kids = [
        h(
          'span',
          {class: 'tag'},
          (TYPE_NAMES[q.type] || q.type) + (q.points ? ' · ' + q.points + ' pts' : ''),
        ),
        h('h2', {style: {marginTop: '10px'}}, q.prompt),
      ];
      if (q.type === 'slide') {
        if (q.body) kids.push(h('p', {style: {whiteSpace: 'pre-wrap'}}, q.body));
        if (q.image)
          kids.push(h('img', {src: q.image, alt: '', style: {maxWidth: '100%', borderRadius: '10px'}}));
        return put(main, ...kids);
      }
      if (q.image)
        kids.push(
          h('img', {
            src: q.image,
            alt: 'Question illustration',
            style: {maxWidth: '100%', borderRadius: '10px', margin: '6px 0 12px'},
          }),
        );
      if (s.phase === 'reveal') {
        kids.push(verdict(s, q));
        if (s.explanation) kids.push(h('p', {class: 'dim'}, s.explanation));
        if (!GRADED.has(q.type)) kids.push(results(s, q));
        if (practice)
          kids.push(
            h(
              'button',
              {class: 'btn primary big', style: {marginTop: '12px'}, onclick: advance},
              s.index + 1 < s.rounds ? 'Next question' : 'Finish',
            ),
          );
        return put(main, ...kids);
      }
      if (q.type === 'spinner') {
        const sp = s.spinner || {};
        kids.push(
          sp.winner
            ? h('div', {class: 'done'}, h('div', {class: 'big'}, '🎯'), h('h2', {}, sp.winner))
            : h('p', {class: 'dim'}, 'Watch the big screen — the wheel is about to spin!'),
        );
        return put(main, ...kids);
      }
      if (q.type === 'qa') {
        kids.push(h('p', {class: 'dim'}, 'Send your question below or with the “? Ask” button.'));
        return put(main, ...kids);
      }
      if (s.phase === 'open' && q.seconds) kids.push(timerBar());
      if (s.phase !== 'open') {
        kids.push(
          h(
            'p',
            {class: 'dim mono'},
            s.phase === 'paused'
              ? '⏸ The presenter paused the timer.'
              : '⏱ Answers are closed. Results are coming…',
          ),
        );
        if (!GRADED.has(q.type)) kids.push(results(s, q));
        return put(main, ...kids);
      }
      if (q.type === 'open') return put(main, ...kids, ideaForm(s, q));
      if (s.me.submitted) {
        kids.push(
          h(
            'div',
            {class: 'done'},
            h('div', {class: 'big'}, '✓'),
            h('h2', {}, 'Answer sent'),
            h('p', {class: 'dim'}, answerText(q, s.me.value)),
          ),
        );
        if (!GRADED.has(q.type)) kids.push(results(s, q));
        return put(main, ...kids);
      }
      kids.push(answerForm(s, q));
      put(main, ...kids);
    }

    function ideaForm(s, q) {
      const left = q.max_entries - (s.me.ideas || 0);
      if (left <= 0)
        return h(
          'p',
          {class: 'dim mono'},
          '✓ Thanks — you shared ' + q.max_entries + (q.max_entries > 1 ? ' ideas.' : ' idea.'),
        );
      const t = h('textarea', {maxlength: 200, placeholder: 'Your idea', 'aria-label': 'Your idea', rows: 3});
      return h(
        'form',
        {
          class: 'stack',
          onsubmit: async e => {
            e.preventDefault();
            if (!t.value.trim()) return;
            await send('/api/idea', {round: s.index, text: t.value});
          },
        },
        t,
        h(
          'button',
          {class: 'btn primary big', type: 'submit'},
          'Share idea' + (q.max_entries > 1 ? ' (' + left + ' left)' : ''),
        ),
      );
    }

    function renderExtra(s) {
      const q = s.question;
      if (!s.me || !q) return put(extra);
      if (q.type === 'open' && s.ideas && s.ideas.length && (q.live_results || s.phase === 'reveal')) {
        const voted = new Set(s.me.voted || []);
        return put(
          extra,
          h('h3', {style: {margin: '18px 0 10px'}}, 'Ideas — tap ▲ to support'),
          s.ideas.map(i =>
            h(
              'div',
              {class: 'idea'},
              h('p', {}, i.body),
              h(
                'button',
                {
                  class: 'vote' + (voted.has(i.id) ? ' on' : ''),
                  disabled: voted.has(i.id) || s.phase !== 'open',
                  onclick: () => send('/api/idea/vote', {id: i.id}),
                },
                '▲ ' + i.votes,
              ),
            ),
          ),
        );
      }
      if (q.type === 'qa') {
        const input = h('input', {type: 'text', maxlength: 240, placeholder: 'Type your question'});
        return put(
          extra,
          h(
            'form',
            {
              class: 'row',
              onsubmit: async e => {
                e.preventDefault();
                if (!input.value.trim()) return;
                await api('/api/ask', {text: input.value});
                input.value = '';
                toast('Sent for review', true);
              },
            },
            input,
            h('button', {class: 'btn primary', type: 'submit'}, 'Send'),
          ),
          (s.qa || []).map(x =>
            h(
              'div',
              {class: 'idea', style: {marginTop: '8px'}},
              h('p', {}, x.body),
              h('button', {class: 'vote', onclick: () => send('/api/vote', {id: x.id})}, '▲ ' + x.votes),
            ),
          ),
        );
      }
      put(extra);
    }

    function answerForm(s, q) {
      const submit = value => send('/api/answer', {round: s.index, value});
      const opts = q.options || [];
      if (q.type === 'choice' || q.type === 'poll') {
        return h(
          'div',
          {class: 'choices'},
          opts.map((o, i) =>
            h(
              'button',
              {
                class: 'choice c' + i,
                onclick: e => {
                  e.currentTarget.classList.add('sel');
                  return submit(o);
                },
              },
              h('span', {class: 'key'}, String.fromCharCode(65 + i)),
              o,
            ),
          ),
        );
      }
      if (q.type === 'multiple') {
        const picked = new Set();
        return h(
          'div',
          {class: 'stack'},
          h('p', {class: 'dim'}, 'Select every correct choice.'),
          h(
            'div',
            {class: 'choices'},
            opts.map((o, i) =>
              h(
                'button',
                {
                  class: 'choice c' + i,
                  onclick: e => {
                    picked.has(o) ? picked.delete(o) : picked.add(o);
                    e.currentTarget.classList.toggle('sel');
                  },
                },
                h('span', {class: 'key'}, String.fromCharCode(65 + i)),
                o,
              ),
            ),
          ),
          h(
            'button',
            {
              class: 'btn primary big',
              onclick: () => (picked.size ? submit([...picked]) : toast('Choose at least one option.')),
            },
            'Submit',
          ),
        );
      }
      if (q.type === 'scale') {
        let pick = 0;
        const btns = Array.from({length: q.scale_max || 5}, (_, i) =>
          h(
            'button',
            {
              onclick: e => {
                pick = i + 1;
                btns.forEach(b => b.classList.remove('sel'));
                e.currentTarget.classList.add('sel');
              },
            },
            String(i + 1),
          ),
        );
        return h(
          'div',
          {class: 'stack'},
          h('div', {class: 'scale'}, btns),
          h(
            'div',
            {class: 'row dim mono'},
            h('span', {}, q.low_label || ''),
            h('span', {class: 'spacer'}),
            h('span', {}, q.high_label || ''),
          ),
          h(
            'button',
            {class: 'btn primary big', onclick: () => (pick ? submit(pick) : toast('Choose a rating.'))},
            'Submit',
          ),
        );
      }
      if (q.type === 'order' || q.type === 'rank') {
        const list = h('div', {class: 'sortable'});
        const items = opts.slice();
        const draw = () =>
          put(
            list,
            ...items.map((v, i) =>
              h(
                'div',
                {class: 'item', 'data-v': v},
                h('span', {class: 'grip', 'aria-hidden': 'true'}, '⠿'),
                h('b', {class: 'mono'}, i + 1 + '.'),
                h('span', {}, v),
                h(
                  'button',
                  {
                    class: 'btn icon',
                    disabled: i === 0,
                    'aria-label': 'Move ' + v + ' up',
                    onclick: () => {
                      [items[i - 1], items[i]] = [items[i], items[i - 1]];
                      draw();
                    },
                  },
                  '↑',
                ),
                h(
                  'button',
                  {
                    class: 'btn icon',
                    disabled: i === items.length - 1,
                    'aria-label': 'Move ' + v + ' down',
                    onclick: () => {
                      [items[i + 1], items[i]] = [items[i], items[i + 1]];
                      draw();
                    },
                  },
                  '↓',
                ),
              ),
            ),
          );
        draw();
        if (window.Sortable)
          window.Sortable.create(list, {
            handle: '.grip',
            animation: 150,
            ghostClass: 'ghost',
            onEnd: () => {
              const now = [...list.children].map(c => c.dataset.v);
              items.splice(0, items.length, ...now);
              draw();
            },
          });
        return h(
          'div',
          {class: 'stack'},
          h(
            'p',
            {class: 'dim'},
            q.type === 'rank'
              ? 'Drag (or use the arrows) — your favourite on top.'
              : 'Drag (or use the arrows) into the correct order.',
          ),
          list,
          h('button', {class: 'btn primary big', onclick: () => submit(items.slice())}, 'Submit order'),
        );
      }
      if (q.type === 'match' || q.type === 'category') {
        const sels = q.labels.map(l =>
          h(
            'select',
            {'aria-label': l},
            h('option', {value: ''}, 'Choose…'),
            opts.map(o => h('option', {value: o}, o)),
          ),
        );
        return h(
          'div',
          {class: 'stack'},
          q.labels.map((l, i) => h('label', {class: 'field'}, l, sels[i])),
          h(
            'button',
            {
              class: 'btn primary big',
              onclick: () =>
                sels.some(x => !x.value) ? toast('Complete every row.') : submit(sels.map(x => x.value)),
            },
            'Submit',
          ),
        );
      }
      const input = h('input', {
        type: q.type === 'number' ? 'number' : 'text',
        step: 'any',
        maxlength: q.type === 'cloud' ? 48 : 180,
        inputmode: q.type === 'number' ? 'decimal' : 'text',
        placeholder: q.type === 'cloud' ? 'One word or short phrase' : 'Your answer',
        'aria-label': 'Your answer',
      });
      setTimeout(() => input.focus(), 50);
      return h(
        'form',
        {
          class: 'stack',
          onsubmit: e => {
            e.preventDefault();
            if (!input.value.trim()) return;
            return submit(q.type === 'number' ? input.valueAsNumber : input.value);
          },
        },
        input,
        h('button', {class: 'btn primary big', type: 'submit'}, 'Submit'),
      );
    }
  }

  // ======================================================================== boot
  const extras =
    mode === 'player'
      ? ['/vendor/Sortable.min.js']
      : [
          '/vendor/wordcloud2.js',
          '/vendor/confetti.browser.js',
          '/vendor/Sortable.min.js',
          '/present.js',
        ].concat(mode === 'edit' ? ['/editor.js'] : []);
  extras
    .reduce((p, src) => p.then(() => loadScript(src)), Promise.resolve())
    .catch(toast)
    .finally(() => {
      if (mode === 'player') player();
      else if (OES.start) OES.start(mode);
    });
})();
