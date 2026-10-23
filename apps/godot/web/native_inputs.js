(() => {
  if (window.__rallyNativeInputs) return;
  const canvas = document.querySelector('#canvas');
  if (!canvas) return;

  // Canvas and inputs share one containing block, including Safari keyboard pans.
  const stage = document.createElement('div');
  stage.id = 'rally-stage';
  stage.style.cssText = 'position:absolute;overflow:hidden;isolation:isolate;';
  canvas.before(stage);
  stage.append(canvas);
  canvas.style.position = 'absolute';
  canvas.style.left = '0';
  canvas.style.top = '0';
  const layer = document.createElement('div');
  layer.id = 'rally-input-layer';
  layer.style.cssText = 'position:absolute;inset:0;pointer-events:none;z-index:20;';
  stage.append(layer);

  const safeArea = document.createElement('div');
  safeArea.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px);';
  document.body.append(safeArea);

  const fields = new Map();
  let latest;
  let revision = 0;
  let frame = 0;
  let viewportKey = '';

  function fitViewport() {
    const viewport = window.visualViewport;
    const width = Math.max(1, viewport?.width ?? window.innerWidth);
    const height = Math.max(1, viewport?.height ?? window.innerHeight);
    const left = viewport?.pageLeft ?? window.scrollX;
    const top = viewport?.pageTop ?? window.scrollY;
    const ratio = window.devicePixelRatio || 1;
    const key = [width,height,left,top,ratio].join(',');
    if (key !== viewportKey) {
      viewportKey = key;
      revision++;
      Object.assign(stage.style,{left:left+'px',top:top+'px',width:width+'px',height:height+'px'});
      // Export policy 0 lets this own the backing size instead of window.innerHeight.
      const pixelWidth = Math.round(width*ratio);
      const pixelHeight = Math.round(height*ratio);
      if (canvas.width !== pixelWidth) canvas.width = pixelWidth;
      if (canvas.height !== pixelHeight) canvas.height = pixelHeight;
      canvas.style.width = width+'px';
      canvas.style.height = height+'px';
    }
  }

  function placeFields() {
    if (!latest) return;
    const bounds = canvas.getBoundingClientRect();
    const origin = layer.getBoundingClientRect();
    const sx = bounds.width/latest.width;
    const sy = bounds.height/latest.height;
    for (const field of latest.fields) {
      const input = fields.get(field.id);
      if (!input) continue;
      Object.assign(input.style,{
        left:(bounds.left-origin.left+field.rect[0]*sx)+'px',
        top:(bounds.top-origin.top+field.rect[1]*sy)+'px',
        width:(field.rect[2]*sx)+'px',height:(field.rect[3]*sy)+'px',
      });
      const top = Math.min(field.rect[3],Math.max(0,latest.clip[1]-field.rect[1]))*sy;
      const bottom = Math.min(field.rect[3],Math.max(0,field.rect[1]+field.rect[3]-latest.clip[1]-latest.clip[3]))*sy;
      input.style.clipPath = 'inset('+top+'px 0 '+bottom+'px 0 round 14px)';
    }
  }

  function schedule() {
    if (frame) return;
    frame = requestAnimationFrame(() => {
      frame = 0;
      fitViewport();
      placeFields();
    });
  }
  window.addEventListener('resize',schedule);
  window.addEventListener('scroll',schedule,{passive:true});
  window.addEventListener('pageshow',schedule);
  window.visualViewport?.addEventListener('resize',schedule);
  window.visualViewport?.addEventListener('scroll',schedule,{passive:true});
  fitViewport();

  window.__rallyNativeInputs = data => {
    latest = data;
    layer.style.opacity = String(data.opacity ?? 1);
    fitViewport();
    const values = {};
    for (const field of data.fields) {
      let input = fields.get(field.id);
      if (!input) {
        input = document.createElement('input');
        input.id = field.id;
        input.type = 'text';
        input.value = field.value;
        input.placeholder = field.placeholder;
        input.maxLength = field.max;
        input.setAttribute('aria-label',field.label);
        input.autocomplete = field.id === 'rally-name' ? 'nickname' : 'off';
        input.setAttribute('autocapitalize',field.id === 'rally-code' ? 'characters' : 'words');
        input.setAttribute('autocorrect','off');
        input.spellcheck = false;
        input.setAttribute('enterkeyhint',field.id === 'rally-name' ? 'next' : 'done');
        input.style.cssText = 'position:absolute;pointer-events:auto;box-sizing:border-box;background:linear-gradient(135deg,#172941,#12213a);color:#f5f6ff;border:1px solid #344864;border-radius:14px;padding:0 14px;font:16px Arial,sans-serif;outline:none;box-shadow:inset 0 1px 1px rgba(255,255,255,.025);';
        input.addEventListener('focus',() => { input.style.borderColor = '#3da8dc'; schedule(); });
        input.addEventListener('blur',() => { input.style.borderColor = '#344864'; schedule(); });
        input.addEventListener('keydown',event => {
          if (event.key !== 'Enter') return;
          event.preventDefault();
          const next = fields.get('rally-code');
          if (field.id === 'rally-name' && next && !next.hidden) next.focus({preventScroll:true});
          else input.blur();
        });
        layer.append(input);
        fields.set(field.id,input);
      }
      // Browser edits own the value while focused, including IME composition.
      if (input.engineValue !== undefined && field.value !== input.engineValue && document.activeElement !== input) input.value = field.value;
      input.engineValue = field.value;
      const visible = data.visible && field.visible !== false;
      if (!visible && document.activeElement === input) input.blur();
      input.hidden = !visible;
      input.style.opacity = String(field.opacity ?? 1);
      values[field.id] = input.value;
    }
    placeFields();
    values.focused = document.activeElement?.id || '';
    values.viewportRevision = revision;
    values.viewportWidth = stage.clientWidth;
    values.viewportHeight = stage.clientHeight;
    const safeStyle = getComputedStyle(safeArea);
    values.safeTop = parseFloat(safeStyle.paddingTop) || 0;
    values.safeBottom = parseFloat(safeStyle.paddingBottom) || 0;
    return JSON.stringify(values);
  };
})();
