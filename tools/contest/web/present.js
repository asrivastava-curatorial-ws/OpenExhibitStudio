'use strict';
/* Shared 16:9 slide renderer, projector view (/display) and presenter console (/host). */
(() => {
  const {h, $, put, api, live, toast, download, TYPE_NAMES, GRADED, answerText} = OES;
  const KEYS = 'ABCDEFGHIJKL';

  /** A 1920×1080 stage scaled to fit its container. */
  function makeStage(container) {
    const wrap = h('div', {class: 'stage-wrap'});
    const st = h('div', {class: 'stage'});
    wrap.append(st);
    container.append(wrap);
    const fit = () => {
      const w = wrap.clientWidth,
        hgt = wrap.clientHeight || (w * 9) / 16;
      const k = Math.min(w / 1920, hgt / 1080);
      st.style.transform = `translate(${(w - 1920 * k) / 2}px,${(hgt - 1080 * k) / 2}px) scale(${k})`;
    };
    new ResizeObserver(fit).observe(wrap);
    fit();
    return {wrap, st, sig: '', cloudSig: '', wheel: {angle: 0, seq: 0}};
  }

  function ring(left, total) {
    const r = 62,
      c = 2 * Math.PI * r,
      f = total ? Math.max(0, left) / total : 0;
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 150 150');
    svg.setAttribute('class', 'ring' + (left < 5 ? ' low' : ''));
    svg.innerHTML = `<circle class="bg" cx="75" cy="75" r="${r}"/><circle class="fg" cx="75" cy="75" r="${r}" stroke-dasharray="${c}" stroke-dashoffset="${c * (1 - f)}" transform="rotate(-90 75 75)"/><text x="75" y="91" text-anchor="middle">${Math.ceil(Math.max(0, left))}</text>`;
    return svg;
  }

  function textBlock(body) {
    const lines = (body || '').split('\n');
    const bullets = lines.filter(l => /^\s*[-•*]\s+/.test(l));
    if (bullets.length && bullets.length === lines.filter(l => l.trim()).length)
      return h(
        'div',
        {class: 'text'},
        h(
          'ul',
          {},
          bullets.map(l => h('li', {}, l.replace(/^\s*[-•*]\s+/, ''))),
        ),
      );
    return h('div', {class: 'text', style: {whiteSpace: 'pre-wrap'}}, body || '');
  }

  /** Update horizontal bars in place so widths animate instead of jumping. */
  function bars(box, rows, {correct = null, order = null} = {}) {
    const max = Math.max(1, ...rows.map(r => r[1]));
    const keyed = new Map([...box.children].map(c => [c.dataset.k, c]));
    const list = order ? order.map(o => [o, (rows.find(r => r[0] === o) || [o, 0])[1]]) : rows;
    put(
      box,
      ...list.map(([label, n], i) => {
        const row = keyed.get(label) || h('div', {class: 'bar', 'data-k': label}, h('span'), h('i'), h('b'));
        row.className =
          'bar c' +
          (order ? order.indexOf(label) % 12 : i % 12) +
          (correct && correct.includes(label) ? ' right' : '');
        row.children[0].textContent = label;
        row.children[2].textContent = n;
        requestAnimationFrame(() => row.children[1].style.setProperty('--w', (100 * n) / max + '%'));
        return row;
      }),
    );
  }

  function wordCloud(box, dist, sv) {
    const sig = JSON.stringify(dist);
    if (sv.cloudSig === sig && box.querySelector('canvas')) return;
    sv.cloudSig = sig;
    const canvas = h('canvas', {width: 1700, height: 640});
    put(box, canvas);
    if (!dist.length) {
      box.append(
        h(
          'p',
          {
            class: 'dim mono',
            style: {position: 'absolute', inset: '40% 0 auto', textAlign: 'center', fontSize: '34px'},
          },
          'Words appear here as people answer',
        ),
      );
      return;
    }
    const max = Math.max(...dist.map(d => d[1]));
    const colors = ['#58a6ff', '#3fb950', '#d29922', '#bc8cff', '#f778ba', '#39c5cf', '#ffa657', '#79c0ff'];
    if (window.WordCloud && window.WordCloud.isSupported) {
      window.WordCloud(canvas, {
        list: dist.map(([w, n]) => [w, 36 + 110 * Math.sqrt(n / max)]),
        fontFamily: 'JetBrains, monospace',
        fontWeight: 700,
        color: () => colors[Math.floor(Math.random() * colors.length)],
        backgroundColor: 'rgba(0,0,0,0)',
        rotateRatio: 0.25,
        rotationSteps: 2,
        gridSize: 14,
        shuffle: false,
        drawOutOfBound: false,
        shrinkToFit: true,
        weightFactor: 1,
      });
    }
  }

  function drawWheel(canvas, entries, angle) {
    const ctx = canvas.getContext('2d'),
      n = entries.length,
      R = canvas.width / 2,
      a = (2 * Math.PI) / Math.max(1, n);
    if (!n) {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.beginPath();
      ctx.arc(R, R, R - 8, 0, 2 * Math.PI);
      ctx.strokeStyle = '#30363d';
      ctx.lineWidth = 6;
      ctx.stroke();
      ctx.fillStyle = '#8b949e';
      ctx.font = '600 34px JetBrains, monospace';
      ctx.textAlign = 'center';
      ctx.fillText('Waiting for entries', R, R);
      return;
    }
    const colors = ['#1f6feb', '#da3633', '#238636', '#9e6a03', '#8957e5', '#1b7c83', '#bf3989', '#6e7681'];
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.save();
    ctx.translate(R, R);
    for (let i = 0; i < n; i++) {
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.arc(0, 0, R - 8, angle + i * a, angle + (i + 1) * a);
      ctx.closePath();
      ctx.fillStyle = colors[i % colors.length];
      ctx.fill();
      ctx.strokeStyle = '#0d1117';
      ctx.lineWidth = 3;
      ctx.stroke();
      if (n <= 48) {
        ctx.save();
        ctx.rotate(angle + (i + 0.5) * a);
        ctx.fillStyle = '#fff';
        ctx.textAlign = 'right';
        ctx.textBaseline = 'middle';
        ctx.font = `700 ${Math.max(16, Math.min(36, 380 / n + 14))}px JetBrains, monospace`;
        const label = entries[i].length > 18 ? entries[i].slice(0, 17) + '…' : entries[i];
        ctx.fillText(label, R - 30, 0);
        ctx.restore();
      }
    }
    ctx.beginPath();
    ctx.arc(0, 0, 46, 0, 2 * Math.PI);
    ctx.fillStyle = '#0d1117';
    ctx.fill();
    ctx.restore();
    ctx.beginPath();
    ctx.moveTo(R - 28, 2);
    ctx.lineTo(R + 28, 2);
    ctx.lineTo(R, 58);
    ctx.closePath();
    ctx.fillStyle = '#e6edf3';
    ctx.fill();
  }

  function spinWheel(canvas, sv, spin, onDone) {
    const entries = spin.entries,
      n = entries.length,
      a = (2 * Math.PI) / n;
    const target = -Math.PI / 2 - (spin.index + 0.5) * a;
    const start = sv.wheel.angle,
      base = start - (start % (2 * Math.PI));
    let end = base + 2 * Math.PI * 6 + (((target % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI));
    if (end - start < 2 * Math.PI * 4) end += 2 * Math.PI * 2;
    const t0 = performance.now(),
      dur = 4800;
    const step = now => {
      const t = Math.min(1, (now - t0) / dur),
        e = 1 - Math.pow(1 - t, 4);
      sv.wheel.angle = start + (end - start) * e;
      drawWheel(canvas, entries, sv.wheel.angle);
      if (t < 1) requestAnimationFrame(step);
      else onDone();
    };
    requestAnimationFrame(step);
  }

  let confettiFire = null;
  function celebrate(container) {
    if (!window.confetti) return;
    let c = container.querySelector('canvas.confetti');
    if (!c) {
      c = h('canvas', {
        class: 'confetti',
        style: {
          position: 'absolute',
          inset: 0,
          width: '100%',
          height: '100%',
          pointerEvents: 'none',
          zIndex: 8,
        },
      });
      container.append(c);
      confettiFire = window.confetti.create(c, {resize: true, useWorker: false});
    }
    const burst = x =>
      confettiFire({particleCount: 120, spread: 80, startVelocity: 55, origin: {x, y: 0.75}});
    burst(0.2);
    setTimeout(() => burst(0.8), 250);
    setTimeout(() => burst(0.5), 500);
  }

  /** Render state `s` into stage view `sv`. opts.preview hides join details for small previews. */
  function render(sv, s, opts = {}) {
    const st = sv.st,
      q = s.question;
    document.body.classList.toggle('light', !!(s.settings && s.settings.theme === 'light'));
    const sig = JSON.stringify([
      s.code,
      s.index,
      s.phase,
      q && q.prompt,
      q && q.type,
      s.answer,
      s.leaders && s.leaders.slice(0, 10),
      s.team_leaders,
      s.phase === 'lobby' && s.roster,
      s.settings,
      opts.preview,
      s.spinner && s.spinner.entries,
    ]);
    const rebuild = sig !== sv.sig;
    if (rebuild) {
      sv.sig = sig;
      sv.cloudSig = '';
      st.replaceChildren();
      if (s.phase === 'lobby') return lobby(st, s, opts);
      if (!opts.preview)
        st.append(
          h(
            'div',
            {class: 'st-top'},
            h('span', {}, 'Join at ', h('b', {}, s.join_host || location.host)),
            h('span', {}, 'code ', h('b', {class: 'code'}, s.code)),
            h('span', {class: 'qr'}, h('img', {src: '/join.svg', alt: 'Join QR code'})),
          ),
        );
      const body = h('div', {class: 'st-body'});
      st.append(body);
      st.append(
        h(
          'div',
          {class: 'st-foot'},
          h('span', {}, s.index >= 0 ? s.index + 1 + ' / ' + s.rounds : ''),
          h('span', {class: 'spacer'}),
          h('span', {id: 'st-count'}),
        ),
      );
      if (s.phase === 'finished') finale(body, s, st);
      else if (s.phase === 'standings') board(body, s);
      else if (q) slide(body, s, q, sv);
    }
    update(sv, s);
  }

  function lobby(st, s, opts) {
    const host = s.join_host || location.host;
    st.append(
      h(
        'div',
        {class: 'st-body'},
        h('div', {class: 'st-kind'}, 'Live session · starting soon'),
        h('h1', {class: 'st-prompt'}, s.title),
        h(
          'div',
          {class: 'lobby'},
          h('div', {class: 'qrbig'}, h('img', {src: '/join.svg', alt: 'Join QR code'})),
          h(
            'div',
            {class: 'how'},
            h('div', {}, 'Scan the code, or open'),
            h('b', {}, host),
            h('div', {}, 'and enter'),
            h('div', {class: 'code'}, s.code),
            h('div', {class: 'dim', id: 'st-joined'}, s.players + ' joined'),
            h(
              'div',
              {class: 'names'},
              (s.roster || []).slice(0, 24).map(r => h('span', {}, r.name)),
            ),
          ),
        ),
      ),
    );
  }

  function slide(body, s, q, sv) {
    const graded = GRADED.has(q.type);
    if (q.type === 'slide') {
      const layout = q.layout || 'auto';
      const wrapCls = layout === 'title' ? 'st-title' : layout === 'big' ? 'st-title st-big' : '';
      const head = h('h1', {class: 'st-prompt' + (q.prompt.length > 70 ? ' long' : '')}, q.prompt);
      const text = q.body ? textBlock(q.body) : null;
      const img = q.image ? h('img', {src: q.image, alt: ''}) : null;
      if (wrapCls) return body.append(h('div', {class: wrapCls}, head, text));
      if (img)
        return body.append(
          head,
          h(
            'div',
            {class: 'st-media', style: {flexDirection: layout === 'image-left' ? 'row-reverse' : 'row'}},
            h('div', {class: 'fill'}, text),
            img,
          ),
        );
      return body.append(head, text);
    }
    const top = h(
      'div',
      {class: 'row', style: {alignItems: 'flex-start', gap: '40px'}},
      h(
        'div',
        {style: {flex: 1}},
        h('div', {class: 'st-kind'}, TYPE_NAMES[q.type] + (q.points ? ' · ' + q.points + ' pts' : '')),
        h('h1', {class: 'st-prompt' + (q.prompt.length > 80 ? ' long' : '')}, q.prompt),
      ),
      h('div', {id: 'st-ring'}),
    );
    body.append(top);
    const area = h('div', {class: 'st-media'});
    const fill = h('div', {class: 'fill'});
    area.append(fill);
    if (q.image) area.append(h('img', {src: q.image, alt: ''}));
    body.append(area);
    const reveal = s.phase === 'reveal';
    if (q.type === 'choice' || q.type === 'multiple' || (q.type === 'poll' && !q.live_results && !reveal)) {
      fill.append(
        h(
          'div',
          {class: 'tiles', id: 'st-tiles'},
          (q.options || []).map((o, i) =>
            h(
              'div',
              {class: 'tile c' + i, 'data-o': o},
              h('span', {class: 'key'}, KEYS[i]),
              h('span', {}, o),
              h('span', {class: 'n'}),
            ),
          ),
        ),
      );
    } else if (q.type === 'poll' || q.type === 'rank') {
      fill.append(h('div', {class: 'bars', id: 'st-bars'}));
    } else if (q.type === 'scale') {
      fill.append(
        h(
          'div',
          {class: 'row', style: {alignItems: 'flex-end', gap: '50px', marginTop: 'auto'}},
          h(
            'div',
            {},
            h('div', {class: 'avg', id: 'st-avg'}, '–'),
            h('div', {class: 'dim mono', style: {fontSize: '26px'}}, 'average of ' + (q.scale_max || 5)),
          ),
          h(
            'div',
            {style: {flex: 1}},
            h(
              'div',
              {class: 'histo', id: 'st-histo'},
              Array.from({length: q.scale_max || 5}, (_, i) =>
                h('div', {'data-v': String(i + 1)}, h('b'), h('i'), h('span', {}, String(i + 1))),
              ),
            ),
            h(
              'div',
              {class: 'scale-labels'},
              h('span', {}, q.low_label || ''),
              h('span', {}, q.high_label || ''),
            ),
          ),
        ),
      );
    } else if (q.type === 'cloud') {
      fill.append(h('div', {class: 'cloud', id: 'st-cloud'}));
    } else if (q.type === 'open') {
      fill.append(h('div', {class: 'ideas', id: 'st-ideas'}));
    } else if (q.type === 'qa') {
      fill.append(h('div', {class: 'qalist', id: 'st-qa'}));
    } else if (q.type === 'spinner') {
      const canvas = h('canvas', {width: 760, height: 760, id: 'st-wheel'});
      fill.append(
        h(
          'div',
          {class: 'wheel'},
          canvas,
          h(
            'div',
            {style: {flex: 1}},
            h(
              'div',
              {class: 'dim mono', style: {fontSize: '30px'}, id: 'st-wheel-note'},
              ((s.spinner && s.spinner.entries.length) || 0) + ' entries',
            ),
            h('div', {class: 'winner', id: 'st-winner'}, (s.spinner && s.spinner.winner) || ''),
          ),
        ),
      );
      drawWheel(canvas, (s.spinner && s.spinner.entries) || [], sv.wheel.angle);
    } else if (reveal && graded) {
      fill.append(
        h(
          'div',
          {style: {marginTop: 'auto'}},
          h('div', {class: 'st-kind', style: {color: 'var(--green)'}}, 'Correct answer'),
          h(
            'div',
            {class: 'st-prompt', style: {color: 'var(--green)', fontSize: '58px'}},
            answerText(q, s.answer),
          ),
        ),
      );
    } else {
      const hint = {
        text: 'Type your answer on your phone',
        number: 'Enter a number on your phone',
        order: 'Put these in order on your phone',
        match: 'Match the pairs on your phone',
        category: 'Sort the items on your phone',
      }[q.type];
      fill.append(
        h(
          'div',
          {style: {marginTop: 'auto'}},
          q.type === 'order'
            ? h(
                'div',
                {class: 'tiles'},
                q.options.map((o, i) =>
                  h('div', {class: 'tile c' + i}, h('span', {class: 'key'}, KEYS[i]), o),
                ),
              )
            : null,
          q.labels
            ? h(
                'div',
                {class: 'tiles'},
                q.labels.map((l, i) =>
                  h('div', {class: 'tile c' + i}, h('span', {class: 'key'}, KEYS[i]), l),
                ),
              )
            : null,
          h('p', {class: 'state-note', style: {color: 'var(--dim)'}}, '📱 ' + hint),
        ),
      );
    }
    if (reveal && s.explanation) body.append(h('div', {class: 'explain'}, s.explanation));
    body.append(h('div', {class: 'state-note', id: 'st-note'}));
  }

  function update(sv, s) {
    const st = sv.st,
      q = s.question;
    const count = st.querySelector('#st-count');
    const answers =
      q &&
      !['slide', 'qa', 'spinner'].includes(q.type) &&
      ['open', 'paused', 'closed', 'reveal'].includes(s.phase);
    if (count)
      count.textContent = answers ? s.received + ' / ' + s.players + ' responded' : s.players + ' joined';
    const joined = st.querySelector('#st-joined');
    if (joined) joined.textContent = s.players + ' joined';
    if (!q || ['lobby', 'standings', 'finished'].includes(s.phase)) return;
    const reveal = s.phase === 'reveal',
      dist = s.distribution || [];
    const note = st.querySelector('#st-note');
    if (note)
      note.textContent =
        s.phase === 'paused'
          ? '⏸ Paused'
          : s.phase === 'closed'
            ? s.received >= s.players && s.players
              ? '✓ Everyone has answered'
              : '⏱ Time is up'
            : (q.type === 'poll' ||
                  q.type === 'cloud' ||
                  q.type === 'scale' ||
                  q.type === 'rank' ||
                  q.type === 'open') &&
                !q.live_results &&
                !reveal
              ? 'Results are hidden until the presenter reveals them'
              : s.reviewing
                ? 'Reviewing an earlier slide'
                : '';
    const ringBox = st.querySelector('#st-ring');
    if (ringBox) {
      put(ringBox);
      if (
        ['open', 'paused'].includes(s.phase) &&
        q.seconds &&
        !['slide', 'qa', 'spinner', 'open'].includes(q.type)
      ) {
        sv.deadline = performance.now() + s.seconds_left * 1000;
        sv.total = q.seconds;
        sv.paused = s.phase === 'paused';
        ringBox.append(ring(s.seconds_left, q.seconds));
      } else sv.deadline = 0;
    }
    const tiles = st.querySelector('#st-tiles');
    if (tiles) {
      const counts = new Map(dist);
      const correct = reveal && q.type !== 'poll' ? (Array.isArray(s.answer) ? s.answer : [s.answer]) : null;
      for (const t of tiles.children) {
        const o = t.dataset.o;
        t.classList.toggle('right', !!correct && correct.includes(o));
        t.classList.toggle('dimmed', !!correct && !correct.includes(o));
        t.querySelector('.n').textContent =
          (reveal || q.live_results) && dist.length ? counts.get(o) || 0 : '';
      }
    }
    const barBox = st.querySelector('#st-bars');
    if (barBox && (q.live_results || reveal))
      bars(barBox, dist, {order: q.type === 'poll' ? q.options : null});
    const histo = st.querySelector('#st-histo');
    if (histo && (q.live_results || reveal)) {
      const counts = new Map(dist.map(([v, n]) => [String(v), n]));
      const max = Math.max(1, ...counts.values());
      let sum = 0,
        n = 0;
      for (const col of histo.children) {
        const c = counts.get(col.dataset.v) || 0;
        sum += c * Number(col.dataset.v);
        n += c;
        col.querySelector('b').textContent = c;
        requestAnimationFrame(() => col.querySelector('i').style.setProperty('--h', (100 * c) / max + '%'));
      }
      st.querySelector('#st-avg').textContent = n ? (sum / n).toFixed(1) : '–';
    }
    const cloud = st.querySelector('#st-cloud');
    if (cloud && (q.live_results || reveal)) wordCloud(cloud, dist, sv);
    else if (cloud && !cloud.childElementCount)
      cloud.append(
        h('p', {class: 'state-note', style: {color: 'var(--dim)'}}, '📱 Send a word from your phone'),
      );
    const ideas = st.querySelector('#st-ideas');
    if (ideas)
      put(
        ideas,
        ...(q.live_results || reveal
          ? (s.ideas || []).filter(i => i.status !== 'hidden' && i.status !== 'pending')
          : []
        )
          .slice(0, 30)
          .map((i, k) =>
            h(
              'div',
              {
                class: 'ic',
                style: {
                  borderLeftColor: ['#58a6ff', '#3fb950', '#d29922', '#bc8cff', '#f778ba', '#39c5cf'][k % 6],
                },
              },
              i.body,
              h('b', {}, '▲ ' + i.votes),
            ),
          ),
      );
    if (ideas && !ideas.childElementCount)
      ideas.append(
        h(
          'p',
          {class: 'state-note', style: {color: 'var(--dim)'}},
          q.live_results || reveal
            ? '📱 Share your ideas from your phone'
            : s.received + ' people have shared ideas',
        ),
      );
    const qa = st.querySelector('#st-qa');
    if (qa) {
      const list = (s.qa || []).filter(x => x.status === 'published' || x.status === 'answered').slice(0, 7);
      put(
        qa,
        ...(list.length
          ? list.map(x =>
              h(
                'div',
                {class: 'q' + (x.status === 'answered' ? ' answered' : '')},
                h('b', {}, '▲ ' + x.votes),
                h('span', {}, x.body),
              ),
            )
          : [
              h(
                'p',
                {class: 'state-note', style: {color: 'var(--dim)'}},
                '📱 Tap “? Ask” on your phone to send a question',
              ),
            ]),
      );
    }
    const wheel = st.querySelector('#st-wheel');
    if (wheel && s.spinner && s.spinner.seq && s.spinner.seq !== sv.wheel.seq) {
      const first = sv.wheel.seq === 0 && !sv.live;
      sv.wheel.seq = s.spinner.seq;
      const win = st.querySelector('#st-winner');
      win.textContent = '';
      if (first) {
        sv.wheel.angle = -Math.PI / 2 - ((s.spinner.index + 0.5) * 2 * Math.PI) / s.spinner.entries.length;
        drawWheel(wheel, s.spinner.entries, sv.wheel.angle);
        win.textContent = s.spinner.winner;
      } else
        spinWheel(wheel, sv, s.spinner, () => {
          win.textContent = '🎉 ' + s.spinner.winner;
          celebrate(sv.wrap);
        });
    }
    sv.live = true;
  }

  function board(body, s) {
    body.append(
      h('div', {class: 'st-kind'}, 'Leaderboard'),
      h('h1', {class: 'st-prompt'}, 'Top scores after ' + (s.index + 1) + (s.index ? ' slides' : ' slide')),
    );
    const cols = h('div', {class: 'board'});
    cols.append(
      h(
        'div',
        {class: 'col'},
        (s.leaders || [])
          .slice(0, 8)
          .map((r, i) =>
            h(
              'div',
              {class: 'rk', style: {animationDelay: i * 70 + 'ms'}},
              h('span', {}, '#' + r.rank),
              h('span', {}, r.name),
              h('b', {}, r.score),
            ),
          ),
      ),
    );
    if ((s.team_leaders || []).length)
      cols.append(
        h(
          'div',
          {class: 'col', style: {flex: '0 0 560px'}},
          h('h3', {style: {fontSize: '34px'}}, 'Teams'),
          s.team_leaders.map((r, i) =>
            h(
              'div',
              {class: 'rk', style: {animationDelay: i * 90 + 'ms'}},
              h('span', {}, '#' + r.rank),
              h('span', {}, r.name),
              h('b', {}, r.score),
            ),
          ),
        ),
      );
    body.append(cols);
  }

  function finale(body, s, st) {
    if (!s.graded_rounds) {
      body.append(
        h(
          'div',
          {class: 'st-title'},
          h('div', {class: 'st-kind'}, s.title),
          h('h1', {class: 'st-prompt', style: {fontSize: '130px'}}, 'Thank you!'),
          h('p', {class: 'dim mono', style: {fontSize: '36px'}}, s.players + ' people took part'),
        ),
      );
      return;
    }
    const top = (s.leaders || []).slice(0, 3);
    body.append(
      h('div', {class: 'st-kind'}, 'Final results'),
      h('h1', {class: 'st-prompt'}, s.title),
      h(
        'div',
        {class: 'podium'},
        [1, 0, 2]
          .filter(i => top[i])
          .map(i =>
            h(
              'div',
              {class: 'p' + (i + 1), style: {animationDelay: (i === 0 ? 900 : i === 1 ? 450 : 0) + 'ms'}},
              top[i].name,
              h('small', {}, top[i].score + ' pts'),
              h('i', {}, '#' + (i + 1)),
            ),
          ),
      ),
    );
    if ((s.team_leaders || []).length)
      body.append(
        h(
          'p',
          {class: 'mono', style: {fontSize: '32px', textAlign: 'center', marginTop: '18px'}},
          'Winning team: ',
          h('b', {style: {color: 'var(--blue)'}}, s.team_leaders[0].name),
        ),
      );
    setTimeout(() => celebrate(st.parentElement), 1200);
  }

  function tickRings(sv) {
    if (!sv.deadline || sv.paused) return;
    const box = sv.st.querySelector('#st-ring');
    if (!box) return;
    const left = (sv.deadline - performance.now()) / 1000;
    put(box, ring(left, sv.total));
  }

  // ====================================================================== projector
  function display() {
    document.body.className = 'display';
    const root = $('#root');
    const sv = makeStage(root);
    const fs = h(
      'button',
      {
        class: 'btn icon fs-btn',
        title: 'Full screen (F)',
        onclick: () =>
          document.fullscreenElement
            ? document.exitFullscreen()
            : document.documentElement.requestFullscreen(),
      },
      '⛶',
    );
    root.append(fs, h('span', {class: 'conn', id: 'conn'}));
    document.addEventListener('keydown', e => {
      if (e.key === 'f' || e.key === 'F') fs.click();
    });
    document.addEventListener('fullscreenchange', () => {
      fs.hidden = !!document.fullscreenElement;
    });
    let reactions = null;
    live(
      '/api/state',
      s => {
        if (!s) return;
        render(sv, s);
        if (reactions)
          for (const [e, n] of Object.entries(s.reactions || {})) {
            const extra = Math.min(8, n - (reactions[e] || 0));
            for (let i = 0; i < extra; i++)
              setTimeout(() => {
                const f = h('div', {class: 'floater', style: {left: 8 + Math.random() * 84 + '%'}}, e);
                sv.wrap.append(f);
                setTimeout(() => f.remove(), 3300);
              }, i * 160);
          }
        reactions = s.reactions || {};
      },
      {withPulse: true},
    );
    setInterval(() => tickRings(sv), 250);
  }

  // ====================================================================== presenter console
  function host() {
    document.body.className = 'host';
    const root = $('#root');
    const top = h(
      'header',
      {class: 'topbar'},
      h('span', {class: 'brand'}, h('i', {}, '◆ '), 'OpenExhibit Live'),
      h('span', {class: 'dim', id: 'h-title'}),
      h('span', {class: 'spacer'}),
      h('span', {class: 'dot', id: 'dot'}),
      h('span', {id: 'h-people', class: 'dim'}),
      h('span', {class: 'room', id: 'h-room'}),
      h('button', {class: 'btn', onclick: () => openProjector()}, '⧉ Projector ', h('kbd', {}, 'F')),
      h('a', {class: 'btn', id: 'h-edit', href: '/edit', target: '_blank', rel: 'noopener'}, '✎ Edit slides'),
      h(
        'button',
        {class: 'btn', onclick: () => exportCsv('/api/host/summary', 'session-summary.csv')},
        '⇩ Summary',
      ),
      h(
        'button',
        {class: 'btn', onclick: () => exportCsv('/api/host/results', 'session-answers.csv')},
        '⇩ Answers',
      ),
      h('button', {class: 'btn danger', onclick: endService}, 'Stop service'),
    );
    const preview = h('div', {class: 'h-preview'});
    const back = h('button', {class: 'btn big', onclick: () => act('back')}, '◀ Back');
    const next = h('button', {class: 'btn big primary next', onclick: () => act('advance')}, 'Start');
    const pause = h('button', {class: 'btn big', onclick: () => act('toggle-pause')}, '⏸ Pause');
    const spin = h('button', {class: 'btn big blue', onclick: () => act('spin')}, '🎡 Spin');
    const lock = h('button', {class: 'btn', onclick: () => act('lock')}, 'Lock joining');
    const status = h('div', {class: 'h-status', id: 'h-status'});
    const help = h('div', {class: 'card lobby-card', id: 'h-help'});
    const main = h(
      'section',
      {class: 'h-main'},
      preview,
      h('div', {class: 'h-controls'}, back, next, pause, spin, h('span', {class: 'spacer'}), lock),
      status,
      help,
    );
    const mini = h('div', {class: 'mini'});
    const notes = h('div', {class: 'notes'});
    const tabs = h('div', {class: 'tabs'});
    const pane = h('div', {class: 'tabpane'});
    const side = h(
      'aside',
      {class: 'h-side'},
      h(
        'div',
        {style: {padding: '14px'}},
        h('div', {class: 'h-status', style: {marginBottom: '6px'}, id: 'h-next'}, 'Next slide'),
        mini,
        h('div', {class: 'h-status', style: {margin: '12px 0 6px'}}, 'Presenter notes'),
        notes,
      ),
      tabs,
      pane,
    );
    root.append(top, h('div', {class: 'h-grid'}, main, side));
    const sv = makeStage(preview),
      mv = makeStage(mini);
    let state = null,
      tab = 'qa',
      paneSig = '',
      projector = null;
    const label = s => {
      const q = s.question,
        graded = q && GRADED.has(q.type),
        last = s.index + 1 >= s.rounds;
      if (s.phase === 'lobby') return s.self_paced ? 'Open self-paced play ▶' : 'Start ▶';
      if (s.phase === 'practice') return 'Finish self-paced ▶';
      if (s.phase === 'finished') return 'Finished';
      if (['open', 'paused', 'closed'].includes(s.phase)) {
        if (graded) return 'Reveal answer ▶';
        if (['poll', 'scale', 'cloud', 'rank', 'open'].includes(q.type) && !q.live_results)
          return 'Show results ▶';
        return last ? 'Finish ▶' : 'Next slide ▶';
      }
      if (s.phase === 'reveal' && graded && !last && s.settings.leaderboard === 'each')
        return 'Leaderboard ▶';
      return last ? 'Show final results ▶' : 'Next slide ▶';
    };
    // Presses are queued and sent one at a time, each against the state that the previous one
    // produced, so a fast double-press on a clicker moves two steps instead of failing.
    const queue = [];
    let sending = false;
    function act(action) {
      if (queue.length < 6) queue.push(action);
      pump();
    }
    const resolve = a => (a === 'toggle-pause' ? (state.phase === 'paused' ? 'resume' : 'pause') : a);
    async function pump() {
      if (sending || !state) return;
      sending = true;
      while (queue.length) {
        let action = resolve(queue.shift());
        if (action === 'advance' && state.phase === 'practice') action = 'finish';
        if (action === 'advance' && state.phase === 'finished') continue;
        try {
          const fresh = await api('/api/host/action', {action, phase: state.phase, round: state.index});
          onHostState(fresh);
        } catch (e) {
          toast(e);
          queue.length = 0;
        }
      }
      sending = false;
    }
    function openProjector() {
      projector = window.open(
        state ? state.audience_url : '/display',
        'oes-projector',
        'popup,width=1280,height=720',
      );
      if (!projector) toast('Allow pop-ups for this page, or open the projector address shown in Studio.');
    }
    async function exportCsv(path, name) {
      const r = await api(path, undefined, true);
      download(await r.blob(), name);
    }
    async function endService() {
      if (
        !confirm(
          'Stop the live service? Phones will disconnect. Results stay in the session database and can be exported after resuming.',
        )
      )
        return;
      await api('/api/host/stop', {});
      document.body.replaceChildren(
        h(
          'div',
          {class: 'card', style: {margin: '60px auto', maxWidth: '520px'}},
          h('h2', {}, 'Service stopped'),
          h('p', {class: 'dim'}, 'You can close this tab.'),
        ),
      );
    }
    document.addEventListener('keydown', e => {
      if (e.target.matches('input,textarea,select')) return;
      const k = e.key;
      if (['ArrowRight', 'PageDown', ' ', 'Enter'].includes(k)) {
        e.preventDefault();
        act('advance');
      } else if (['ArrowLeft', 'PageUp'].includes(k)) {
        e.preventDefault();
        act('back');
      } else if (k === 'p' || k === 'P') act('toggle-pause');
      else if (k === 's' || k === 'S') act('spin');
      else if (k === 'f' || k === 'F') openProjector();
      else if (k === 'l' || k === 'L') act('lock');
    });
    setInterval(() => tickRings(sv), 250);
    live('/api/host/state', (s, err) => onHostState(s, err));
    function onHostState(s, err) {
      if (s && state && s.version < state.version) return; // an older long-poll reply arrived late
      if (!s) {
        document.body.replaceChildren(
          h(
            'div',
            {class: 'card', style: {margin: '60px auto', maxWidth: '560px'}},
            h('h2', {}, 'Presenter link expired'),
            h('p', {}, err ? err.message : ''),
            h(
              'p',
              {class: 'dim'},
              'Open the presenter again from OpenExhibit Studio (Live audience → Present), or use the link printed by tools/quiz.py.',
            ),
          ),
        );
        return;
      }
      state = s;
      $('#h-title').textContent = s.title;
      $('#h-room').textContent = s.code;
      $('#h-people').textContent = s.players + ' joined';
      render(sv, s, {preview: false});
      const q = s.question,
        idx = s.index;
      next.textContent = label(s);
      next.disabled = s.phase === 'finished';
      back.disabled = idx <= 0 || ['lobby', 'practice'].includes(s.phase);
      pause.hidden =
        !['open', 'paused'].includes(s.phase) || !q || ['slide', 'qa', 'spinner'].includes(q.type);
      pause.textContent = s.phase === 'paused' ? '▶ Resume' : '⏸ Pause';
      spin.hidden = !(q && q.type === 'spinner') || s.phase === 'lobby';
      lock.textContent = s.locked ? 'Open joining' : 'Lock joining';
      $('#h-edit').hidden = s.phase !== 'lobby';
      status.textContent =
        s.phase === 'lobby'
          ? 'Lobby · waiting to start'
          : `Slide ${idx + 1} of ${s.rounds} · ${q ? TYPE_NAMES[q.type] : ''} · ${s.phase}${s.reviewing ? ' (review)' : ''}` +
            (q && !['slide', 'qa', 'spinner'].includes(q.type)
              ? ` · ${s.received}/${s.players} responded`
              : '');
      help.hidden = s.phase !== 'lobby';
      if (s.phase === 'lobby')
        put(
          help,
          h('h3', {}, 'Ready when you are'),
          h(
            'p',
            {},
            'Open the projector window (F) and drag it to the projector screen, then press ',
            h('b', {}, 'F11'),
            ' there for full screen.',
          ),
          h(
            'p',
            {},
            'People join at ',
            h('b', {class: 'mono'}, s.join_url),
            ' — or scan the QR on the projector.',
          ),
          h(
            'p',
            {class: 'dim'},
            'Keys: → / Space / clicker = next · ← = back · P = pause · S = spin · L = lock joining.',
          ),
        );
      const upcoming = s.deck.questions[idx + 1];
      $('#h-next').textContent = upcoming
        ? `Next · ${idx + 2}. ${TYPE_NAMES[upcoming.type]}`
        : 'Next · end of session';
      if (upcoming)
        render(
          mv,
          {
            ...s,
            phase: 'open',
            index: idx + 1,
            question: upcoming,
            distribution: [],
            answer: null,
            ideas: [],
            qa: s.qa,
            spinner: {
              entries:
                upcoming.source === 'players' ? (s.roster || []).map(r => r.name) : upcoming.options || [],
              seq: 0,
            },
            seconds_left: upcoming.seconds,
            received: 0,
            reviewing: false,
          },
          {preview: true},
        );
      else {
        mv.sig = '';
        mv.st.replaceChildren(
          h(
            'div',
            {class: 'st-title', style: {position: 'absolute', inset: '0', alignItems: 'center'}},
            h('h1', {class: 'st-prompt'}, 'End'),
          ),
        );
      }
      const cur = idx >= 0 ? s.deck.questions[idx] : null;
      notes.textContent = cur && cur.notes ? cur.notes : '—';
      sidePane(s);
    }
    function sidePane(s) {
      const pending = s.qa.filter(x => x.status === 'pending').length;
      const showIdeas = s.question && s.question.type === 'open';
      if (tab === 'ideas' && !showIdeas) tab = 'qa';
      const sig = JSON.stringify([tab, s.qa, s.ideas, s.roster, s.players]);
      put(
        tabs,
        h(
          'button',
          {
            class: tab === 'qa' ? 'on' : '',
            onclick: () => {
              tab = 'qa';
              paneSig = '';
              sidePane(state);
            },
          },
          'Q&A ',
          h('span', {}, pending ? '(' + pending + ' new)' : ''),
        ),
        showIdeas
          ? h(
              'button',
              {
                class: tab === 'ideas' ? 'on' : '',
                onclick: () => {
                  tab = 'ideas';
                  paneSig = '';
                  sidePane(state);
                },
              },
              'Ideas ',
              h('span', {}, '(' + (s.ideas || []).length + ')'),
            )
          : null,
        h(
          'button',
          {
            class: tab === 'people' ? 'on' : '',
            onclick: () => {
              tab = 'people';
              paneSig = '';
              sidePane(state);
            },
          },
          'People ',
          h('span', {}, '(' + s.players + ')'),
        ),
      );
      if (sig === paneSig) return;
      paneSig = sig;
      if (tab === 'qa')
        put(
          pane,
          s.qa.length
            ? null
            : h(
                'p',
                {class: 'dim'},
                'Audience questions arrive here for approval before anyone else sees them.',
              ),
          s.qa.map(x =>
            h(
              'div',
              {class: 'qrow ' + x.status},
              h('div', {}, x.body),
              h(
                'div',
                {class: 'row'},
                h('span', {class: 'tag'}, x.status),
                h('span', {class: 'dim mono'}, '▲ ' + x.votes),
                h('span', {class: 'spacer'}),
                [
                  ['published', 'Show'],
                  ['answered', 'Answered'],
                  ['hidden', 'Hide'],
                ]
                  .filter(([st]) => st !== x.status)
                  .map(([st, t]) =>
                    h(
                      'button',
                      {
                        class: 'btn icon',
                        onclick: () => api('/api/host/moderate', {id: x.id, status: st}).catch(toast),
                      },
                      t,
                    ),
                  ),
              ),
            ),
          ),
        );
      else if (tab === 'ideas')
        put(
          pane,
          (s.ideas || []).map(x =>
            h(
              'div',
              {class: 'qrow ' + (x.status === 'shown' ? '' : x.status)},
              h('div', {}, x.body),
              h(
                'div',
                {class: 'row'},
                h('span', {class: 'tag'}, x.status),
                h('span', {class: 'dim mono'}, '▲ ' + x.votes),
                h('span', {class: 'spacer'}),
                h(
                  'button',
                  {
                    class: 'btn icon',
                    onclick: () =>
                      api('/api/host/moderate-idea', {
                        id: x.id,
                        status: x.status === 'shown' ? 'hidden' : 'shown',
                      }).catch(toast),
                  },
                  x.status === 'shown' ? 'Hide' : 'Show',
                ),
              ),
            ),
          ),
        );
      else
        put(
          pane,
          h('p', {class: 'dim'}, s.players + ' joined' + (s.locked ? ' · joining locked' : '')),
          h(
            'div',
            {class: 'people'},
            (s.roster || []).map(r => h('span', {}, r.name + (r.team ? ' · ' + r.team : ''))),
          ),
        );
    }
  }

  OES.makeStage = makeStage;
  OES.renderStage = render;
  OES.start = mode => {
    if (mode === 'display') display();
    else if (mode === 'host') host();
    else if (OES.editor) OES.editor();
  };
})();
