/* Offline firmware block editor (Blockly 12, vendored). */
(function () {
  'use strict';
  const $ = id => document.getElementById(id);
  const B = window.Blockly;
  if (!B) {
    $('status').textContent = 'Blockly could not load (vendor/blockly is missing from this installation).';
    return;
  }

  const digital = () => window.EXHIBIT_BOARDS[$('board').value].digital.map(p => [p, p]);
  const analog = () => window.EXHIBIT_BOARDS[$('board').value].analog.map(p => [p, p]);
  B.defineBlocksWithJsonArray([
    {
      type: 'oes_analog',
      message0: 'analog sensor on %1 → channel %2',
      tooltip: 'Potentiometer, light sensor, temperature sensor… reports 0–1023.',
      args0: [
        {type: 'field_dropdown', name: 'PIN', options: analog},
        {type: 'field_input', name: 'CHANNEL', text: 'dial'},
      ],
      previousStatement: null,
      nextStatement: null,
      colour: 210,
    },
    {
      type: 'oes_button',
      message0: 'push button on pin %1 → channel %2',
      tooltip: 'Wire the button between the pin and GND. Reports 1 while pressed.',
      args0: [
        {type: 'field_dropdown', name: 'PIN', options: digital},
        {type: 'field_input', name: 'CHANNEL', text: 'button'},
      ],
      previousStatement: null,
      nextStatement: null,
      colour: 120,
    },
    {
      type: 'oes_switch',
      message0: 'switch or motion sensor on pin %1 → channel %2',
      tooltip: 'PIR, reed or Hall sensor whose output is HIGH when active. Reports 1 or 0.',
      args0: [
        {type: 'field_dropdown', name: 'PIN', options: digital},
        {type: 'field_input', name: 'CHANNEL', text: 'presence'},
      ],
      previousStatement: null,
      nextStatement: null,
      colour: 120,
    },
    {
      type: 'oes_distance',
      message0: 'distance sensor TRIG %1 ECHO %2 → channel %3',
      tooltip: 'HC-SR04 ultrasonic sensor. Reports centimetres.',
      args0: [
        {type: 'field_dropdown', name: 'PIN', options: digital},
        {type: 'field_dropdown', name: 'PIN2', options: digital},
        {type: 'field_input', name: 'CHANNEL', text: 'distance'},
      ],
      previousStatement: null,
      nextStatement: null,
      colour: 30,
    },
  ]);

  const theme = B.Theme.defineTheme('oes-dark', {
    base: B.Themes.Classic,
    componentStyles: {
      workspaceBackgroundColour: '#0d1117',
      toolboxBackgroundColour: '#161b22',
      toolboxForegroundColour: '#e6edf3',
      flyoutBackgroundColour: '#161b22',
      flyoutForegroundColour: '#e6edf3',
      scrollbarColour: '#30363d',
      insertionMarkerColour: '#58a6ff',
    },
    fontStyle: {family: 'JetBrains Mono, monospace', size: 11},
  });
  const workspace = B.inject('workspace', {
    media: 'vendor/blockly/media/',
    theme,
    sounds: false,
    trashcan: true,
    zoom: {controls: true, wheel: true},
    toolbox: {
      kind: 'flyoutToolbox',
      contents: ['oes_analog', 'oes_button', 'oes_switch', 'oes_distance'].map(type => ({
        kind: 'block',
        type,
      })),
    },
  });

  const saved = localStorage.getItem('oes-firmware-blocks');
  try {
    if (saved) B.serialization.workspaces.load(JSON.parse(saved), workspace);
  } catch (e) {
    /* an older layout: start fresh */
  }
  if (!workspace.getAllBlocks(false).length) {
    const first = workspace.newBlock('oes_analog');
    first.initSvg();
    first.render();
    first.moveBy(40, 40);
  }

  function blocksInOrder() {
    const ordered = [];
    for (const top of workspace.getTopBlocks(true))
      for (let b = top; b; b = b.getNextBlock())
        ordered.push({
          type: b.type,
          pin: b.getFieldValue('PIN'),
          pin2: b.getFieldValue('PIN2'),
          channel: b.getFieldValue('CHANNEL'),
        });
    return ordered;
  }
  function refresh() {
    try {
      $('code').textContent = window.generateExhibitSketch(blocksInOrder(), {
        board: $('board').value,
        interval: $('interval').value,
      });
      $('status').textContent = 'Ready — export the sketch and upload it with Arduino IDE or Arduino CLI.';
      $('status').className = '';
      $('save').disabled = $('copy').disabled = false;
    } catch (err) {
      $('status').textContent = err.message;
      $('status').className = 'problem';
      $('save').disabled = $('copy').disabled = true;
    }
    localStorage.setItem('oes-firmware-blocks', JSON.stringify(B.serialization.workspaces.save(workspace)));
  }
  workspace.addChangeListener(e => {
    if (!e.isUiEvent) refresh();
  });
  $('board').addEventListener('change', refresh);
  $('interval').addEventListener('input', refresh);
  $('save').addEventListener('click', () => {
    const url = URL.createObjectURL(new Blob([$('code').textContent], {type: 'text/plain'}));
    const a = Object.assign(document.createElement('a'), {href: url, download: 'ExhibitInputs.ino'});
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 3000);
  });
  $('copy').addEventListener('click', () =>
    navigator.clipboard.writeText($('code').textContent).then(() => {
      $('status').textContent = 'Copied to the clipboard.';
    }),
  );
  refresh();
})();
