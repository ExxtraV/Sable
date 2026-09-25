// The download buttons point at the newest release's disk image (or zip), asking GitHub which that is.
// If the request fails, the buttons keep their fallback link to the releases page.
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
      buttons.forEach(function (button) { button.href = pick.browser_download_url; });
      document.querySelectorAll('[data-download-note]').forEach(function (note) {
        var mb = Math.round(pick.size / 104857.6) / 10;
        note.textContent = (release.tag_name ? release.tag_name + ', ' : '') + mb + ' MB ' + (isDisk ? 'disk image' : 'zip archive');
        note.hidden = false;
      });
    })
    .catch(function () {});
})();

// Paragraph Focus for screenshots: the one nearest the middle of the window is at full strength.
// Skipped when the visitor has asked for reduced motion; the screenshots then simply stay at full strength.
(function () {
  if (!('IntersectionObserver' in window) || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  var shots = document.querySelectorAll('.part .shot');
  if (!shots.length) return;
  document.documentElement.classList.add('focusing');
  var observer = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) { entry.target.classList.toggle('in-focus', entry.isIntersecting); });
  }, { rootMargin: '-30% 0px -30% 0px' });
  shots.forEach(function (shot) { observer.observe(shot); });
})();
