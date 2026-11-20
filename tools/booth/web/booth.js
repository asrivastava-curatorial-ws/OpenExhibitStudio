'use strict';
/*
 * OpenExhibit green-screen booth. Runs on the booth computer (browsers allow the camera only on a
 * local address), opened from Studio or by tools/greenscreen.py. BoothKeyer composites the keyed
 * camera over the current background on #stage; photos are JPEG snapshots of that canvas and clips
 * are recorded from a 1280 × 720 copy of it, then sent to the service, which answers with a code
 * for the QR download.
 *
 * Keys: ←/→ background · Space/Enter photo · R video · Esc close · F full screen ·
 *       Ctrl+Shift+S setup (camera, keying, placement).
 * The URL fragment carries the service token, optionally followed by "&setup".
 */
(() => {
  const {Compositor, chromaOf, distance, sizeOf} = window.BoothKeyer;
  const $ = id => document.getElementById(id);
  const body = document.body;
  const stage = $('stage');

  const fragment = location.hash.slice(1).split('&');
  if (fragment[0]) sessionStorage.setItem('booth-token', fragment[0]);
  const token = sessionStorage.getItem('booth-token') || '';
  history.replaceState(null, '', location.pathname); // keep the token out of the address bar

  const RECORDING_TYPES = [
    'video/mp4;codecs=avc1.42E01F', // plays on every phone, where the browser can record it
    'video/mp4;codecs=avc1',
    'video/mp4',
    'video/webm;codecs=vp9',
    'video/webm;codecs=vp8',
    'video/webm',
  ];
  const RESULT_SECONDS = 60;

  const state = {
    settings: null,
    backgrounds: [], // {name, kind, fit, element}
    overlay: null,
    index: 0,
    localOnly: false,
    camera: Object.assign(document.createElement('video'), {muted: true, playsInline: true}),
    stream: null,
    busy: false,
    lastSeen: 0, // someone was in front of the screen
    lastTouch: Date.now(), // someone used the controls
    lastCycle: Date.now(),
    recording: null,
    matte: false,
    picking: false,
    resultTimer: 0,
  };
  let compositor = null;

  // ------------------------------------------------------------------ helpers
  function h(tag, props = {}, ...children) {
    const el = document.createElement(tag);
    for (const [key, value] of Object.entries(props)) {
      if (key.startsWith('on')) el.addEventListener(key.slice(2), value);
      else if (key in el) el[key] = value;
      else el.setAttribute(key, value);
    }
    el.append(...children.flat().filter(child => child !== null && child !== undefined && child !== false));
    return el;
  }

  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  const hex = rgb => '#' + rgb.map(v => Math.round(v).toString(16).padStart(2, '0')).join('');
  const touch = () => (state.lastTouch = Date.now());

  async function api(path, options = {}) {
    const response = await fetch(path, {
      ...options,
      headers: {Authorization: 'Bearer ' + token, ...(options.headers || {})},
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.error || `Request failed (${response.status}).`);
    return data;
  }

  function message(text, seconds = 6) {
    const box = $('message');
    box.textContent = text;
    box.hidden = !text;
    clearTimeout(message.timer);
    if (text && seconds) message.timer = setTimeout(() => (box.hidden = true), seconds * 1000);
  }

  let sound = null;
  function beep(frequency = 880, seconds = 0.08) {
    try {
      sound = sound || new AudioContext();
      const tone = sound.createOscillator();
      const gain = sound.createGain();
      tone.frequency.value = frequency;
      gain.gain.setValueAtTime(0.15, sound.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.0001, sound.currentTime + seconds);
      tone.connect(gain).connect(sound.destination);
      tone.start();
      tone.stop(sound.currentTime + seconds);
    } catch {
      // Sound is a nicety; the booth works silently.
    }
  }

  function restartAnimation(element, name) {
    element.classList.remove(name);
    void element.offsetWidth; // reflow so the animation runs again
    element.classList.add(name);
  }

  // ------------------------------------------------------------------ backgrounds
  function loadBackgrounds(list) {
    state.backgrounds = list.map(item => {
      const element =
        item.kind === 'video'
          ? h('video', {muted: true, loop: true, playsInline: true, preload: 'auto', src: item.url})
          : h('img', {src: item.url, alt: ''});
      element.addEventListener('error', () =>
        message(
          `The background “${item.name}” cannot be shown. Use WebM or MP4 video, or PNG/JPEG pictures.`,
          12,
        ),
      );
      return {...item, element};
    });
    const nav = $('backgrounds');
    nav.replaceChildren(
      ...state.backgrounds.map((item, i) =>
        h('button', {type: 'button', onclick: () => (touch(), select(i))}, item.name),
      ),
    );
    nav.hidden = state.backgrounds.length < 2;
    select(0);
  }

  function select(index) {
    const count = state.backgrounds.length;
    if (!count) return;
    state.index = ((index % count) + count) % count;
    state.backgrounds.forEach((item, i) => {
      if (item.kind !== 'video') return;
      if (i === state.index) item.element.play().catch(() => {});
      else item.element.pause();
    });
    body.dataset.background = String(state.index);
    [...$('backgrounds').children].forEach((chip, i) => chip.classList.toggle('on', i === state.index));
  }

  // ------------------------------------------------------------------ camera
  async function startCamera() {
    state.stream?.getTracks().forEach(track => track.stop());
    state.stream = null;
    body.dataset.camera = 'starting';
    if (!navigator.mediaDevices?.getUserMedia) {
      body.dataset.camera = 'error';
      message('The camera needs a current browser and the local booth address (127.0.0.1).', 0);
      return;
    }
    const wanted = {width: {ideal: 1920}, height: {ideal: 1080}, frameRate: {ideal: 30}};
    try {
      let stream = await navigator.mediaDevices.getUserMedia({video: wanted, audio: false});
      const preferred = state.settings.camera;
      if (preferred && stream.getVideoTracks()[0]?.label !== preferred) {
        const devices = await navigator.mediaDevices.enumerateDevices();
        const match = devices.find(d => d.kind === 'videoinput' && d.label === preferred);
        if (match) {
          stream.getTracks().forEach(track => track.stop());
          stream = await navigator.mediaDevices.getUserMedia({
            video: {...wanted, deviceId: {exact: match.deviceId}},
            audio: false,
          });
        }
      }
      state.stream = stream;
      state.camera.srcObject = stream;
      await state.camera.play();
      body.dataset.camera = 'live';
      message('');
    } catch (error) {
      body.dataset.camera = 'error';
      const reasons = {
        NotAllowedError:
          'Camera access is blocked. Allow the camera for this page (camera icon in the address bar), then reload.',
        NotFoundError: 'No camera found. Plug in a webcam or capture card, then reload.',
        NotReadableError: 'The camera is in use by another program. Close that program, then reload.',
        OverconstrainedError: 'The chosen camera is not available. Pick another one in setup (Ctrl+Shift+S).',
      };
      message(reasons[error.name] || `The camera could not start: ${error.message}`, 0);
    }
  }

  // Low-resolution copy of the camera picture for presence detection and colour detection.
  const sampler = Object.assign(document.createElement('canvas'), {width: 96, height: 54});
  const sampling = sampler.getContext('2d', {willReadFrequently: true});

  /** Texture-space region kept by the crop (the crop is given as visitors see the picture). */
  function keptRegion() {
    const {crop} = state.settings.person;
    const [left, top, right, bottom] = crop;
    return state.settings.mirror ? [right, top, 1 - left, 1 - bottom] : [left, top, 1 - right, 1 - bottom];
  }

  /** Share of the kept camera picture that is not key colour: someone is in front of the screen. */
  function coverage() {
    if (!sizeOf(state.camera)) return 0;
    const {width: W, height: H} = sampler;
    sampling.drawImage(state.camera, 0, 0, W, H);
    const {data} = sampling.getImageData(0, 0, W, H);
    const {key} = state.settings;
    const target = chromaOf(key.color);
    const limit = key.tolerance + key.softness;
    const [u0, v0, u1, v1] = keptRegion();
    let inside = 0;
    let person = 0;
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        const u = (x + 0.5) / W;
        const v = (y + 0.5) / H;
        if (u < u0 || u > u1 || v < v0 || v > v1) continue;
        const i = (y * W + x) * 4;
        inside++;
        if (distance(data[i], data[i + 1], data[i + 2], target) > limit) person++;
      }
    }
    return inside ? person / inside : 0;
  }

  /** Median colour of the camera picture's left, right and top edges: the screen itself. */
  function detectKey() {
    if (!sizeOf(state.camera)) return null;
    const {width: W, height: H} = sampler;
    sampling.drawImage(state.camera, 0, 0, W, H);
    const {data} = sampling.getImageData(0, 0, W, H);
    const channels = [[], [], []];
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        if (x >= W * 0.12 && x < W * 0.88 && y >= H * 0.12) continue;
        const i = (y * W + x) * 4;
        for (let c = 0; c < 3; c++) channels[c].push(data[i + c]);
      }
    }
    return hex(channels.map(values => values.sort((a, b) => a - b)[values.length >> 1]));
  }

  /** Colour of the camera picture under a click on the stage (5 × 5 average). */
  function colourAt(event) {
    const size = sizeOf(state.camera);
    if (!size) return null;
    const box = stage.getBoundingClientRect();
    const scale = Math.min(box.width / stage.width, box.height / stage.height);
    const x = (event.clientX - box.left - (box.width - stage.width * scale) / 2) / scale;
    const y = (event.clientY - box.top - (box.height - stage.height * scale) / 2) / scale;
    const rect = compositor.personRect(size, state.settings.person, state.settings.mirror);
    let u = (x - rect.x) / rect.w;
    const v = (y - rect.y) / rect.h;
    if (u < 0 || u > 1 || v < 0 || v > 1) return null;
    if (state.settings.mirror) u = 1 - u;
    const grab = Object.assign(document.createElement('canvas'), {width: size.w, height: size.h});
    const context = grab.getContext('2d', {willReadFrequently: true});
    context.drawImage(state.camera, 0, 0);
    const px = Math.min(size.w - 5, Math.max(0, Math.round(u * size.w) - 2));
    const py = Math.min(size.h - 5, Math.max(0, Math.round(v * size.h) - 2));
    const {data} = context.getImageData(px, py, 5, 5);
    const sum = [0, 0, 0];
    for (let i = 0; i < data.length; i += 4) for (let c = 0; c < 3; c++) sum[c] += data[i + c];
    return hex(sum.map(total => total / 25));
  }

  // ------------------------------------------------------------------ drawing and idle behaviour
  function frame() {
    const background = state.backgrounds[state.index];
    compositor.draw({
      background: background?.element,
      fit: background?.fit,
      camera: body.dataset.camera === 'live' ? state.camera : null,
      overlay: state.overlay,
      settings: state.settings,
      matte: state.matte,
    });
    state.recording?.copy();
    requestAnimationFrame(frame);
  }

  function watch() {
    if (body.dataset.camera !== 'live') return;
    const present = coverage() > 0.03;
    const now = Date.now();
    if (present) state.lastSeen = now;
    body.dataset.present = present ? 'yes' : 'no';
    const cycle = state.settings.cycle_seconds * 1000;
    const idle = now - Math.max(state.lastSeen, state.lastTouch);
    if (cycle && !state.busy && !present && idle > cycle && now - state.lastCycle > cycle) {
      state.lastCycle = now;
      select(state.index + 1);
    }
  }

  // ------------------------------------------------------------------ photos and clips
  async function countdown(seconds) {
    const box = $('countdown');
    for (let n = seconds; n > 0; n--) {
      box.textContent = String(n);
      box.hidden = false;
      restartAnimation(box, 'tick');
      beep(660);
      await sleep(1000);
    }
    box.hidden = true;
  }

  async function capture(kind, produce) {
    if (state.busy || body.dataset.camera !== 'live') return;
    state.busy = true;
    body.dataset.busy = 'yes';
    closeResult();
    try {
      const blob = await produce();
      message(kind === 'photo' ? 'Preparing your photo…' : 'Preparing your video…', 0);
      const data = await api('/api/capture', {
        method: 'POST',
        headers: {'Content-Type': blob.type},
        body: blob,
      });
      message('');
      showResult(data);
    } catch (error) {
      message(error.message || 'Something went wrong. Please try again.');
    } finally {
      state.busy = false;
      body.dataset.busy = 'no';
      touch();
    }
  }

  function takePhoto() {
    if (!state.settings?.photo) return;
    return capture('photo', async () => {
      await countdown(state.settings.countdown);
      beep(1320, 0.12);
      restartAnimation($('flash'), 'go');
      return new Promise((resolve, reject) =>
        stage.toBlob(
          blob => (blob ? resolve(blob) : reject(new Error('The photo could not be taken.'))),
          'image/jpeg',
          0.92,
        ),
      );
    });
  }

  function recordClip() {
    if (!state.settings?.clip) return;
    const type =
      typeof MediaRecorder === 'function' && RECORDING_TYPES.find(t => MediaRecorder.isTypeSupported(t));
    if (!type) return message('This browser cannot record video.');
    return capture('clip', async () => {
      await countdown(state.settings.countdown);
      const canvas = h('canvas', {width: 1280, height: 720});
      const context = canvas.getContext('2d');
      const copy = () => context.drawImage(stage, 0, 0, canvas.width, canvas.height);
      copy();
      const recorder = new MediaRecorder(canvas.captureStream(30), {
        mimeType: type,
        videoBitsPerSecond: 5_000_000,
      });
      const parts = [];
      recorder.ondataavailable = event => event.data.size && parts.push(event.data);
      const stopped = new Promise(resolve => (recorder.onstop = resolve));
      const seconds = state.settings.clip_seconds;
      const indicator = $('recording');
      try {
        state.recording = {copy};
        recorder.start(500);
        beep(990, 0.12);
        indicator.hidden = false;
        const started = performance.now();
        for (let left = seconds; left > 0; left = seconds - (performance.now() - started) / 1000) {
          $('rec-left').textContent = `${Math.ceil(left)} s`;
          await sleep(100);
        }
      } finally {
        if (recorder.state !== 'inactive') recorder.stop();
        await stopped;
        state.recording = null;
        indicator.hidden = true;
      }
      beep(660, 0.12);
      return new Blob(parts, {type: type.split(';')[0]});
    });
  }

  function showResult(data) {
    const panel = $('result');
    panel.dataset.code = data.code;
    $('qr').src = `/qr/${data.code}.svg`;
    $('result-title').textContent =
      data.kind === 'photo' ? 'Scan to take your photo home' : 'Scan to take your video home';
    $('result-url').textContent = data.url;
    $('result-note').textContent = state.localOnly
      ? 'Phones cannot reach this computer yet: in Studio, choose the local network under “Who can download”.'
      : `Kept until ${data.expires_text}, then deleted. Nothing goes to the internet.`;
    panel.hidden = false;
    restartAnimation(panel, 'run');
    clearTimeout(state.resultTimer);
    state.resultTimer = setTimeout(closeResult, RESULT_SECONDS * 1000);
  }

  function closeResult() {
    clearTimeout(state.resultTimer);
    $('result').hidden = true;
  }

  // ------------------------------------------------------------------ setup panel (operator)
  function toggleSetup(open = $('setup').hidden) {
    const panel = $('setup');
    if (open) buildSetup();
    panel.hidden = !open;
    if (!open) {
      state.matte = false;
      setPicking(false);
    }
  }

  function setPicking(on) {
    state.picking = on;
    body.dataset.picking = on ? 'yes' : 'no';
  }

  function buildSetup() {
    const s = state.settings;
    const colour = h('input', {
      type: 'color',
      value: s.key.color,
      oninput: () => (s.key.color = colour.value),
    });
    const setColour = value => {
      if (!value) return;
      s.key.color = value;
      colour.value = value;
    };
    const slider = (label, read, write, min, max, step) => {
      const output = h('output');
      const input = h('input', {type: 'range', min, max, step, value: read()});
      const show = () => (output.value = Number(input.value).toFixed(step < 1 ? 2 : 0));
      input.addEventListener('input', () => (write(Number(input.value)), show()));
      show();
      return h('label', {className: 'slider'}, h('span', {}, label), input, output);
    };
    const check = (label, read, write) =>
      h(
        'label',
        {className: 'row'},
        h('input', {type: 'checkbox', checked: read(), onchange: event => write(event.target.checked)}),
        label,
      );
    const cameras = h('select', {
      onchange: () => {
        s.camera = cameras.value;
        startCamera();
      },
    });
    navigator.mediaDevices
      ?.enumerateDevices()
      .then(devices => {
        const videos = devices.filter(d => d.kind === 'videoinput');
        const current = state.stream?.getVideoTracks()[0]?.label || s.camera;
        cameras.replaceChildren(
          ...videos.map((d, i) =>
            h('option', {value: d.label, selected: d.label === current}, d.label || `Camera ${i + 1}`),
          ),
        );
      })
      .catch(() => {});
    const crop = i => [() => s.person.crop[i], value => (s.person.crop[i] = value), 0, 0.45, 0.01];
    $('setup').replaceChildren(
      h('h2', {}, 'Booth setup'),
      h(
        'p',
        {},
        'Light the cloth evenly and keep people a step or two in front of it. Adjust until the matte shows people white and the cloth black.',
      ),
      h('h3', {}, 'Camera'),
      cameras,
      check(
        'Mirror (selfie view)',
        () => s.mirror,
        value => (s.mirror = value),
      ),
      h('h3', {}, 'Key colour'),
      h(
        'div',
        {className: 'row'},
        colour,
        h('button', {type: 'button', onclick: () => setColour(detectKey())}, 'Detect from edges'),
        h(
          'button',
          {type: 'button', onclick: () => (setPicking(true), message('Click the cloth in the picture.', 4))},
          'Pick on picture',
        ),
        h('button', {type: 'button', onclick: () => setColour('#00b140')}, 'Green'),
        h('button', {type: 'button', onclick: () => setColour('#0047bb')}, 'Blue'),
      ),
      slider(
        'Tolerance',
        () => s.key.tolerance,
        v => (s.key.tolerance = v),
        0,
        0.6,
        0.01,
      ),
      slider(
        'Softness',
        () => s.key.softness,
        v => (s.key.softness = v),
        0.01,
        0.4,
        0.01,
      ),
      slider(
        'Spill removal',
        () => s.key.spill,
        v => (s.key.spill = v),
        0,
        1,
        0.01,
      ),
      check(
        'Show matte (white = kept)',
        () => state.matte,
        value => (state.matte = value),
      ),
      h('h3', {}, 'Placement'),
      slider(
        'Size',
        () => s.person.scale,
        v => (s.person.scale = v),
        0.3,
        2.5,
        0.01,
      ),
      slider(
        'Left – right',
        () => s.person.x,
        v => (s.person.x = v),
        0,
        1,
        0.01,
      ),
      slider(
        'Up – down',
        () => s.person.y,
        v => (s.person.y = v),
        0.5,
        1.5,
        0.01,
      ),
      h('h3', {}, 'Trim the camera picture'),
      slider('Left', ...crop(0)),
      slider('Top', ...crop(1)),
      slider('Right', ...crop(2)),
      slider('Bottom', ...crop(3)),
      h(
        'div',
        {className: 'row'},
        h('button', {type: 'button', className: 'primary', onclick: saveSettings}, 'Save'),
        h('button', {type: 'button', onclick: () => toggleSetup(false)}, 'Close'),
      ),
      h('p', {}, 'Studio keeps these settings with “Save booth settings into this exhibit”.'),
    );
  }

  async function saveSettings() {
    try {
      const reply = await api('/api/settings', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({settings: state.settings}),
      });
      state.settings = reply.settings;
      message('Booth settings saved.', 3);
      buildSetup();
    } catch (error) {
      message(error.message);
    }
  }

  // ------------------------------------------------------------------ input
  function toggleFullscreen() {
    if (document.fullscreenElement) document.exitFullscreen();
    else document.documentElement.requestFullscreen().catch(() => {});
  }

  document.addEventListener('keydown', event => {
    if (event.ctrlKey && event.shiftKey && event.code === 'KeyS') {
      event.preventDefault();
      toggleSetup();
      return;
    }
    if (event.target.closest?.('#setup') || !state.settings) return;
    touch();
    if (event.key === 'ArrowRight') select(state.index + 1);
    else if (event.key === 'ArrowLeft') select(state.index - 1);
    else if (event.key === ' ' || event.key === 'Enter') {
      event.preventDefault();
      takePhoto();
    } else if (event.key === 'r' || event.key === 'R') recordClip();
    else if (event.key === 'Escape') (closeResult(), setPicking(false));
    else if (event.key === 'f' || event.key === 'F') toggleFullscreen();
  });

  stage.addEventListener('click', event => {
    if (!state.picking) return;
    const picked = colourAt(event);
    if (!picked) return message('Click on the camera picture.', 3);
    state.settings.key.color = picked;
    setPicking(false);
    buildSetup();
  });
  stage.addEventListener('dblclick', () => state.picking || toggleFullscreen());
  $('photo').addEventListener('click', () => (touch(), takePhoto()));
  $('clip').addEventListener('click', () => (touch(), recordClip()));
  $('done').addEventListener('click', closeResult);

  // ------------------------------------------------------------------ start
  async function start() {
    try {
      compositor = new Compositor(stage);
    } catch (error) {
      body.dataset.camera = 'error';
      message(error.message, 0);
      return;
    }
    let booth;
    try {
      booth = await api('/api/booth');
    } catch (error) {
      message(`${error.message} Open the booth from Studio (Green screen → Open booth).`, 0);
      return;
    }
    state.settings = booth.settings;
    state.localOnly = booth.local_only;
    document.title = booth.settings.title;
    $('title').textContent = booth.settings.title;
    $('photo').hidden = !booth.settings.photo;
    $('clip').hidden = !booth.settings.clip;
    if (booth.overlay) state.overlay = h('img', {src: booth.overlay, alt: ''});
    loadBackgrounds(booth.backgrounds);
    if (!booth.backgrounds.length)
      message('No backgrounds yet: add videos or pictures in Studio → Green screen.', 0);
    else if (booth.warnings.length) message(booth.warnings.join(' · '), 15);
    requestAnimationFrame(frame);
    setInterval(watch, 400);
    await startCamera();
    if (fragment.includes('setup')) toggleSetup(true);
  }

  start();
})();
