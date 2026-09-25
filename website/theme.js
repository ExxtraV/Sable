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
  document.addEventListener('DOMContentLoaded', function () {
    apply(current());
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
