'use strict';
/*
 * WebGL compositor for the green-screen booth. Each frame draws, into one canvas:
 *   1. the background picture or video (cover or contain),
 *   2. the camera picture with the key colour removed,
 *   3. an optional overlay picture (frame, logo) stretched over the whole canvas.
 * The same canvas is the source for photos and clips, so they match what visitors see.
 *
 * Keying: each camera pixel's distance from the key colour is measured in the CbCr colour plane
 * (BT.709), averaged over its 3 × 3 neighbourhood to calm sensor and compression noise, and turned
 * into transparency with a soft threshold (tolerance, softness). Spill removal limits the key's
 * dominant channel (green for a green screen) to the larger of the other two, which removes the
 * green glow the cloth throws onto hair and shoulders without touching skin tones.
 */
window.BoothKeyer = (() => {
  const VERTEX = `
    attribute vec2 a_pos;
    attribute vec2 a_uv;
    uniform vec2 u_canvas;
    varying vec2 v_uv;
    void main() {
      vec2 clip = a_pos / u_canvas * 2.0 - 1.0;
      gl_Position = vec4(clip.x, -clip.y, 0.0, 1.0);
      v_uv = a_uv;
    }`;

  const PLAIN = `
    precision mediump float;
    uniform sampler2D u_image;
    varying vec2 v_uv;
    void main() {
      gl_FragColor = texture2D(u_image, v_uv);
    }`;

  const KEYED = `
    precision mediump float;
    uniform sampler2D u_image;
    uniform vec2 u_texel;
    uniform vec2 u_key;
    uniform float u_tolerance;
    uniform float u_softness;
    uniform float u_spill;
    uniform vec3 u_axis;
    uniform vec4 u_keep;
    uniform float u_matte;
    varying vec2 v_uv;

    vec2 chroma(vec3 c) {
      return vec2(-0.1146 * c.r - 0.3854 * c.g + 0.5 * c.b, 0.5 * c.r - 0.4542 * c.g - 0.0458 * c.b);
    }

    void main() {
      vec4 colour = texture2D(u_image, v_uv);
      float total = 0.0;
      for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
          vec3 near = texture2D(u_image, v_uv + vec2(float(dx), float(dy)) * u_texel).rgb;
          total += distance(chroma(near), u_key);
        }
      }
      float alpha = clamp((total / 9.0 - u_tolerance) / u_softness, 0.0, 1.0);
      if (v_uv.x < u_keep.x || v_uv.y < u_keep.y || v_uv.x > u_keep.z || v_uv.y > u_keep.w) {
        alpha = 0.0;
      }
      float dominant = dot(colour.rgb, u_axis);
      vec3 rest = colour.rgb * (vec3(1.0) - u_axis);
      float other = max(max(rest.r, rest.g), rest.b);
      colour.rgb -= u_axis * max(dominant - other, 0.0) * u_spill;
      gl_FragColor = u_matte > 0.5 ? vec4(vec3(alpha), 1.0) : vec4(colour.rgb, alpha);
    }`;

  /** CbCr of an sRGB colour given as #rrggbb (the same formula as the shader). */
  function chromaOf(hex) {
    const [r, g, b] = rgbOf(hex);
    return [-0.1146 * r - 0.3854 * g + 0.5 * b, 0.5 * r - 0.4542 * g - 0.0458 * b];
  }

  function rgbOf(hex) {
    const n = parseInt(hex.slice(1), 16);
    return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
  }

  /** One-hot vector of the key colour's strongest channel (spill is removed from that channel). */
  function axisOf(hex) {
    const rgb = rgbOf(hex);
    const top = rgb.indexOf(Math.max(...rgb));
    return [0, 1, 2].map(i => (i === top ? 1 : 0));
  }

  /** Visible part of a source of aspect `source` drawn into a frame of aspect `frame`. */
  function fit(mode, source, frame, width, height) {
    if (mode === 'contain') {
      const scale = Math.min(width / source.w, height / source.h);
      const w = source.w * scale;
      const h = source.h * scale;
      return {x: (width - w) / 2, y: (height - h) / 2, w, h, u0: 0, v0: 0, u1: 1, v1: 1};
    }
    const sourceAspect = source.w / source.h;
    if (sourceAspect > frame) {
      const keep = frame / sourceAspect;
      return {x: 0, y: 0, w: width, h: height, u0: (1 - keep) / 2, v0: 0, u1: (1 + keep) / 2, v1: 1};
    }
    const keep = sourceAspect / frame;
    return {x: 0, y: 0, w: width, h: height, u0: 0, v0: (1 - keep) / 2, u1: 1, v1: (1 + keep) / 2};
  }

  function sizeOf(source) {
    if (!source) return null;
    if (source instanceof HTMLVideoElement) {
      return source.readyState >= 2 && source.videoWidth
        ? {w: source.videoWidth, h: source.videoHeight}
        : null;
    }
    return source.complete && source.naturalWidth ? {w: source.naturalWidth, h: source.naturalHeight} : null;
  }

  class Compositor {
    constructor(canvas) {
      const gl = canvas.getContext('webgl', {
        alpha: false,
        antialias: false,
        premultipliedAlpha: false,
        preserveDrawingBuffer: true, // photos read the canvas after it was drawn
      });
      if (!gl) throw new Error('This browser cannot use WebGL, which the green screen needs.');
      this.gl = gl;
      this.canvas = canvas;
      this.plain = this.program(PLAIN);
      this.keyed = this.program(KEYED);
      this.buffer = gl.createBuffer();
      this.textures = new Map();
      gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    }

    program(fragment) {
      const gl = this.gl;
      const compile = (type, source) => {
        const shader = gl.createShader(type);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader));
        return shader;
      };
      const program = gl.createProgram();
      gl.attachShader(program, compile(gl.VERTEX_SHADER, VERTEX));
      gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragment));
      gl.linkProgram(program);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
      const uniforms = {};
      for (let i = 0; i < gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS); i++) {
        const name = gl.getActiveUniform(program, i).name;
        uniforms[name] = gl.getUniformLocation(program, name);
      }
      return {
        program,
        uniforms,
        pos: gl.getAttribLocation(program, 'a_pos'),
        uv: gl.getAttribLocation(program, 'a_uv'),
      };
    }

    /** Uploads a picture or the current video frame; pictures are uploaded once. */
    texture(source) {
      const gl = this.gl;
      let entry = this.textures.get(source);
      if (!entry) {
        const texture = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, texture);
        for (const [name, value] of [
          [gl.TEXTURE_MIN_FILTER, gl.LINEAR],
          [gl.TEXTURE_MAG_FILTER, gl.LINEAR],
          [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE],
          [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE],
        ]) {
          gl.texParameteri(gl.TEXTURE_2D, name, value);
        }
        entry = {texture, uploaded: false};
        this.textures.set(source, entry);
      }
      gl.bindTexture(gl.TEXTURE_2D, entry.texture);
      if (source instanceof HTMLVideoElement || !entry.uploaded) {
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, source);
        entry.uploaded = true;
      }
      return entry.texture;
    }

    forget(source) {
      const entry = this.textures.get(source);
      if (entry) this.gl.deleteTexture(entry.texture);
      this.textures.delete(source);
    }

    quad(shader, rect) {
      const gl = this.gl;
      const {x, y, w, h, u0, v0, u1, v1} = rect;
      // Two triangles; x, y (canvas pixels) and u, v per vertex.
      // prettier-ignore
      const data = new Float32Array([
        x, y, u0, v0, x + w, y, u1, v0, x, y + h, u0, v1,
        x, y + h, u0, v1, x + w, y, u1, v0, x + w, y + h, u1, v1,
      ]);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
      gl.bufferData(gl.ARRAY_BUFFER, data, gl.STREAM_DRAW);
      gl.enableVertexAttribArray(shader.pos);
      gl.vertexAttribPointer(shader.pos, 2, gl.FLOAT, false, 16, 0);
      gl.enableVertexAttribArray(shader.uv);
      gl.vertexAttribPointer(shader.uv, 2, gl.FLOAT, false, 16, 8);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
    }

    use(shader, source) {
      const gl = this.gl;
      gl.useProgram(shader.program);
      gl.activeTexture(gl.TEXTURE0);
      this.texture(source);
      gl.uniform1i(shader.uniforms.u_image, 0);
      gl.uniform2f(shader.uniforms.u_canvas, this.canvas.width, this.canvas.height);
    }

    /**
     * Where the camera picture lands on the canvas: its bottom centre at (x, y) of the canvas,
     * `scale` times the canvas height tall. Returns the rectangle and texture coordinates.
     */
    personRect(camera, person, mirror) {
      const W = this.canvas.width;
      const H = this.canvas.height;
      const h = person.scale * H;
      const w = (h * camera.w) / camera.h;
      return {
        x: person.x * W - w / 2,
        y: person.y * H - h,
        w,
        h,
        u0: mirror ? 1 : 0,
        u1: mirror ? 0 : 1,
        v0: 0,
        v1: 1,
      };
    }

    /** Draws one frame. `scene` = {background, fit, camera, overlay, settings, matte}. */
    draw(scene) {
      const gl = this.gl;
      const W = this.canvas.width;
      const H = this.canvas.height;
      gl.viewport(0, 0, W, H);
      gl.clearColor(0.05, 0.07, 0.09, 1);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.disable(gl.BLEND);
      const backgroundSize = sizeOf(scene.background);
      if (backgroundSize && !scene.matte) {
        this.use(this.plain, scene.background);
        this.quad(this.plain, fit(scene.fit, backgroundSize, W / H, W, H));
      }
      const cameraSize = sizeOf(scene.camera);
      if (cameraSize) {
        const {key, person, mirror} = scene.settings;
        const shader = this.keyed;
        this.use(shader, scene.camera);
        const u = shader.uniforms;
        const [cb, cr] = chromaOf(key.color);
        const [left, top, right, bottom] = person.crop;
        gl.uniform2f(u.u_texel, 1 / cameraSize.w, 1 / cameraSize.h);
        gl.uniform2f(u.u_key, cb, cr);
        gl.uniform1f(u.u_tolerance, key.tolerance);
        gl.uniform1f(u.u_softness, Math.max(key.softness, 0.005));
        gl.uniform1f(u.u_spill, key.spill);
        gl.uniform3fv(u.u_axis, axisOf(key.color));
        // The crop is given for the picture as visitors see it; mirror it into texture space.
        const keep = mirror ? [right, top, 1 - left, 1 - bottom] : [left, top, 1 - right, 1 - bottom];
        gl.uniform4fv(u.u_keep, keep);
        gl.uniform1f(u.u_matte, scene.matte ? 1 : 0);
        if (!scene.matte) {
          gl.enable(gl.BLEND);
          gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        }
        this.quad(shader, this.personRect(cameraSize, person, mirror));
      }
      if (sizeOf(scene.overlay) && !scene.matte) {
        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        this.use(this.plain, scene.overlay);
        this.quad(this.plain, {x: 0, y: 0, w: W, h: H, u0: 0, v0: 0, u1: 1, v1: 1});
      }
    }
  }

  /** Chroma distance of an sRGB pixel (0–255 channels) from a key given as CbCr. */
  function distance(r, g, b, key) {
    const cb = (-0.1146 * r - 0.3854 * g + 0.5 * b) / 255;
    const cr = (0.5 * r - 0.4542 * g - 0.0458 * b) / 255;
    return Math.hypot(cb - key[0], cr - key[1]);
  }

  return {Compositor, chromaOf, distance, sizeOf};
})();
