(function () {
  var root = document.documentElement;

  // The menu button on small screens.
  var btn = document.querySelector('.nav-toggle');
  var nav = document.getElementById('site-nav');
  if (btn && nav) {
    root.classList.add('js');
    var set = function (open) {
      root.classList.toggle('nav-open', open);
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
    };
    btn.addEventListener('click', function () { set(!root.classList.contains('nav-open')); });
    nav.addEventListener('click', function (e) { if (e.target.tagName === 'A') set(false); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') set(false); });
    window.addEventListener('resize', function () { if (window.innerWidth > 1024) set(false); });
  }

  // Pictures open in a pop-up over the page instead of a new page. Click, Escape or the close button closes it, and the
  // arrow keys step to the next and previous picture.
  var pictures = Array.prototype.slice.call(document.querySelectorAll('main img')).filter(function (img) {
    return !/icon\.png|logo-/.test(img.getAttribute('src') || '');
  });
  if (!pictures.length) return;

  var box = document.createElement('div');
  box.className = 'lightbox';
  box.setAttribute('role', 'dialog');
  box.setAttribute('aria-modal', 'true');
  box.setAttribute('aria-label', 'Picture');
  box.hidden = true;
  box.innerHTML = '<button type="button" class="lightbox-close" aria-label="Close">&times;</button>' +
    '<button type="button" class="lightbox-step lightbox-prev" aria-label="Previous picture">&#8249;</button>' +
    '<figure class="lightbox-figure"><img alt=""><figcaption></figcaption></figure>' +
    '<button type="button" class="lightbox-step lightbox-next" aria-label="Next picture">&#8250;</button>';
  document.body.appendChild(box);
  var shown = box.querySelector('img');
  var caption = box.querySelector('figcaption');
  var current = -1;
  var opener = null;

  function show(index) {
    current = (index + pictures.length) % pictures.length;
    var img = pictures[current];
    shown.src = img.currentSrc || img.src;
    shown.alt = img.alt || '';
    var figure = img.closest('figure');
    var text = figure && figure.querySelector('figcaption');
    caption.textContent = text ? text.textContent : (img.alt || '');
    box.classList.toggle('single', pictures.length < 2);
  }

  function open(index, from) {
    opener = from || null;
    show(index);
    box.hidden = false;
    root.classList.add('lightbox-open');
    box.querySelector('.lightbox-close').focus();
  }

  function close() {
    box.hidden = true;
    root.classList.remove('lightbox-open');
    shown.removeAttribute('src');
    if (opener && opener.focus) opener.focus();
  }

  pictures.forEach(function (img, index) {
    img.classList.add('zoomable');
    var link = img.closest('a');
    var target = link || img;
    if (!link) { img.tabIndex = 0; img.setAttribute('role', 'button'); }
    target.addEventListener('click', function (e) { e.preventDefault(); open(index, target); });
    if (!link) img.addEventListener('keydown', function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); open(index, img); } });
  });

  box.addEventListener('click', function (e) {
    if (e.target.closest('.lightbox-prev')) { show(current - 1); return; }
    if (e.target.closest('.lightbox-next')) { show(current + 1); return; }
    close();
  });
  document.addEventListener('keydown', function (e) {
    if (box.hidden) return;
    if (e.key === 'Escape') close();
    else if (e.key === 'ArrowLeft') show(current - 1);
    else if (e.key === 'ArrowRight') show(current + 1);
  });
})();
