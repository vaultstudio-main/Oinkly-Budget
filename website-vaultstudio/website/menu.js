(function () {
  var root = document.documentElement;
  var btn = document.querySelector('.nav-toggle');
  var nav = document.getElementById('site-nav');
  if (!btn || !nav) return;
  root.classList.add('js');
  function set(open) {
    root.classList.toggle('nav-open', open);
    btn.setAttribute('aria-expanded', open ? 'true' : 'false');
  }
  btn.addEventListener('click', function () { set(!root.classList.contains('nav-open')); });
  nav.addEventListener('click', function (e) { if (e.target.tagName === 'A') set(false); });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') set(false); });
  window.addEventListener('resize', function () { if (window.innerWidth > 1024) set(false); });
})();
