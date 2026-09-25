// The site comes in three of Sable's own themes: Paper (light), Midnight (dark), and Arcane.
// This runs in <head>, before the page draws, so a visitor's choice never flashes the wrong colors.
// With no choice saved, the site follows the Mac's light or dark setting (Paper or Midnight).
(function () {
  var themes = { paper: '#FAFAF8', midnight: '#131820', arcane: '#1B1330' };
  var root = document.documentElement;
  var dark = window.matchMedia('(prefers-color-scheme: dark)');
  function saved() {
    try { var t = localStorage.getItem('sable-theme'); return themes[t] ? t : null; } catch (e) { return null; }
  }
  function apply(theme) {
    root.setAttribute('data-theme', theme);
    var metas = document.querySelectorAll('meta[name="theme-color"]');
    for (var i = 0; i < metas.length; i++) metas[i].setAttribute('content', themes[theme]);
    var buttons = document.querySelectorAll('[data-set-theme]');
    for (var j = 0; j < buttons.length; j++) {
      buttons[j].setAttribute('aria-pressed', String(buttons[j].getAttribute('data-set-theme') === theme));
    }
  }
  function current() { return saved() || (dark.matches ? 'midnight' : 'paper'); }
  apply(current());
  if (dark.addEventListener) dark.addEventListener('change', function () { apply(current()); });
  // Arcane's motes, drawn the way the app's ParticleField draws them: 44 small dots, 1.2 to 2.8 points
  // across, each drifting upward at 1.2% to 5% of the window height per second and twinkling softly.
  // Like the app, there are none at all when the visitor has asked to reduce motion.
  var still = window.matchMedia('(prefers-reduced-motion: reduce)');
  var canvas = null, frame = 0, motes = [];
  var seed = 7;
  function random() { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; }
  for (var m = 0; m < 44; m++) {
    motes.push({ x: random(), y: random(), size: 1.2 + random() * 1.6, speed: 0.012 + random() * 0.038, phase: random() });
  }
  function draw(time) {
    var t = time / 1000, ratio = window.devicePixelRatio || 1;
    var w = window.innerWidth, h = window.innerHeight;
    if (canvas.width !== Math.round(w * ratio) || canvas.height !== Math.round(h * ratio)) {
      canvas.width = Math.round(w * ratio); canvas.height = Math.round(h * ratio);
    }
    var ctx = canvas.getContext('2d');
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = '#E9DFFB';
    for (var i = 0; i < motes.length; i++) {
      var mote = motes[i];
      var y = (mote.y - t * mote.speed) % 1; if (y < 0) y += 1;
      ctx.globalAlpha = (0.35 + 0.5 * (0.5 + 0.5 * Math.sin(t * 0.6 + mote.phase * Math.PI * 2))) * 0.55;
      ctx.beginPath();
      ctx.arc(mote.x * w, y * h, mote.size / 2, 0, Math.PI * 2);
      ctx.fill();
    }
    frame = requestAnimationFrame(draw);
  }
  function updateMotes() {
    var on = root.getAttribute('data-theme') === 'arcane' && !still.matches && document.body;
    if (on && !canvas) {
      canvas = document.createElement('canvas');
      canvas.className = 'motes';
      canvas.setAttribute('aria-hidden', 'true');
      document.body.appendChild(canvas);
      frame = requestAnimationFrame(draw);
    } else if (!on && canvas) {
      cancelAnimationFrame(frame);
      canvas.remove();
      canvas = null;
    }
  }
  new MutationObserver(updateMotes).observe(root, { attributes: true, attributeFilter: ['data-theme'] });
  if (still.addEventListener) still.addEventListener('change', updateMotes);

  document.addEventListener('DOMContentLoaded', function () {
    apply(current());
    updateMotes();
    root.classList.add('themes-ready');
    var buttons = document.querySelectorAll('[data-set-theme]');
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].addEventListener('click', function () {
        var theme = this.getAttribute('data-set-theme');
        try { localStorage.setItem('sable-theme', theme); } catch (e) {}
        apply(theme);
      });
    }
  });
})();
