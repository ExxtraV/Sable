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
