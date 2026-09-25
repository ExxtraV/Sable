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

// The tour. Each step has its own clip of the real app. With Reduce Motion (or an old browser) nothing
// plays by itself: the clips show their still frame and get controls, so playing one is the visitor's choice.
// Otherwise, on wide screens one pinned window plays the clip for the step in the middle of the window and
// pauses the rest; on narrow screens each clip plays while it's on screen. A Pause button stops all of it.
(function () {
  var tour = document.querySelector('.tour');
  if (!tour) return;
  var steps = [].slice.call(tour.querySelectorAll('.step'));
  var clips = steps.map(function (step) { return step.querySelector('video'); });
  if (!('IntersectionObserver' in window) || window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    clips.forEach(function (clip) { clip.controls = true; });
    return;
  }
  tour.classList.add('tour-live');
  var wide = window.matchMedia('(min-width: 960px)');
  var stage = tour.querySelector('.tour-stage');
  var screen = stage.querySelector('.screen');
  var button = stage.querySelector('.motion');
  stage.hidden = false;
  var staged = clips.map(function (clip) {
    var copy = clip.cloneNode(false);
    copy.muted = true;
    copy.setAttribute('aria-hidden', 'true');
    copy.removeAttribute('aria-label');
    screen.appendChild(copy);
    return copy;
  });
  var paused = false;
  var active = 0;
  var onScreen = [];
  function play(clip) {
    if (paused) return;
    clip.preload = 'auto';
    var promise = clip.play();
    if (promise && promise.catch) promise.catch(function () {});
  }
  function showStep(index) {
    active = index;
    steps.forEach(function (step, i) { step.classList.toggle('active', i === index); });
    if (!wide.matches) return;
    staged.forEach(function (clip, i) {
      clip.classList.toggle('on', i === index);
      if (i === index) { play(clip); } else { clip.pause(); }
      if (i === index + 1) clip.preload = 'auto';
    });
  }
  // Wide screens: the step crossing the middle of the window is the active one.
  // A short settle time means a quick scroll past a step doesn't flip its clip on and off.
  var pending = null;
  var middle = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      clearTimeout(pending);
      var index = steps.indexOf(entry.target);
      pending = setTimeout(function () { showStep(index); }, 250);
    });
  }, { rootMargin: '-45% 0px -45% 0px' });
  steps.forEach(function (step) { middle.observe(step); });
  // Narrow screens: each clip plays while most of it is on screen.
  var inline = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      var visible = entry.intersectionRatio >= 0.6;
      onScreen = onScreen.filter(function (clip) { return clip !== entry.target; });
      if (visible) onScreen.push(entry.target);
      if (wide.matches) return;
      if (visible) { play(entry.target); } else { entry.target.pause(); }
    });
  }, { threshold: [0, 0.6] });
  clips.forEach(function (clip) {
    inline.observe(clip);
    clip.addEventListener('click', function () { setPaused(!paused); });
  });
  function setPaused(value) {
    paused = value;
    button.textContent = paused ? 'Play' : 'Pause';
    button.setAttribute('aria-pressed', String(paused));
    staged.concat(clips).forEach(function (clip) { clip.pause(); });
    if (paused) return;
    if (wide.matches) { showStep(active); } else { onScreen.forEach(play); }
  }
  button.addEventListener('click', function () { setPaused(!paused); });
  // Browsers may hold back a clip that starts while it's still fading in or loading; nudge the active one.
  staged.forEach(function (clip, i) {
    ['canplay', 'transitionend'].forEach(function (name) {
      clip.addEventListener(name, function () {
        if (wide.matches && i === active && clip.classList.contains('on') && clip.paused) play(clip);
      });
    });
  });
  wide.addEventListener('change', function () {
    staged.concat(clips).forEach(function (clip) { clip.pause(); });
    if (wide.matches) { showStep(active); } else { onScreen.forEach(play); }
  });
})();
