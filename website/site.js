(function () {
  var app = document.getElementById('app');
  if (!app) return;
  var swatches = document.querySelectorAll('.swatch');
  swatches.forEach(function (button) {
    button.addEventListener('click', function () {
      app.setAttribute('data-theme', button.getAttribute('data-theme'));
      swatches.forEach(function (other) { other.setAttribute('aria-pressed', String(other === button)); });
    });
  });
})();

// Bring each editorial section in gently as it enters the page. The stylesheet
// respects the visitor's Reduce Motion setting, so this never becomes required motion.
(function () {
  var sections = document.querySelectorAll('.reveal');
  if (!sections.length) return;
  if (!('IntersectionObserver' in window) || window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    sections.forEach(function (item) { item.classList.add('visible'); });
    return;
  }
  var observer = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) { entry.target.classList.add('visible'); observer.unobserve(entry.target); }
    });
  }, { threshold: .12 });
  sections.forEach(function (item) { observer.observe(item); });
})();

// The download button points at the newest release's disk image (or zip), asking GitHub which that is.
// If the request fails, the button keeps its fallback link to the releases page.
(function () {
  var buttons = document.querySelectorAll('[data-download]');
  if (!buttons.length || !window.fetch) return;
  fetch('https://api.github.com/repos/ExxtraV/Sable/releases/latest', { headers: { Accept: 'application/vnd.github+json' } })
    .then(function (response) { return response.ok ? response.json() : Promise.reject(); })
    .then(function (release) {
      var assets = release.assets || [];
      var pick = assets.filter(function (a) { return /\.dmg$/i.test(a.name); })[0] || assets.filter(function (a) { return /\.zip$/i.test(a.name); })[0];
      if (!pick) return;
      var isDisk = /\.dmg$/i.test(pick.name);
      buttons.forEach(function (button) {
        button.href = pick.browser_download_url;
        button.textContent = 'Download ' + (release.tag_name || 'the latest release');
      });
      document.querySelectorAll('[data-download-note]').forEach(function (note) {
        var mb = Math.round(pick.size / 104857.6) / 10;
        note.textContent = (release.tag_name || '') + ' · ' + mb + ' MB · ' + (isDisk ? 'disk image' : 'zip archive');
        note.hidden = false;
      });
      document.querySelectorAll('[data-install-steps]').forEach(function (steps) { steps.setAttribute('data-kind', isDisk ? 'dmg' : 'zip'); });
      document.querySelectorAll('[data-version-label]').forEach(function (label) {
        label.textContent = label.getAttribute('data-version-label') + (release.tag_name || '').replace(/^v/, '');
      });
    })
    .catch(function () {});
})();
