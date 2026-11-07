// Mobile nav toggle
document.addEventListener('DOMContentLoaded', () => {
  const toggle = document.querySelector('.nav-toggle');
  const links = document.querySelector('.nav-links');
  if (toggle && links) {
    toggle.addEventListener('click', () => {
      const isOpen = links.classList.toggle('open');
      toggle.setAttribute('aria-expanded', String(isOpen));
    });
    links.querySelectorAll('a').forEach((link) => {
      link.addEventListener('click', () => {
        links.classList.remove('open');
        toggle.setAttribute('aria-expanded', 'false');
      });
    });
  }

  // Back to top: fades in at the bottom left once the page is scrolled past
  // the first screen, so short pages never show it.
  const toTop = document.createElement('button');
  toTop.type = 'button';
  toTop.className = 'to-top';
  toTop.setAttribute('aria-label', 'Back to top');
  toTop.innerHTML =
    '<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">' +
    '<path d="M12 19V5M5 12l7-7 7 7" fill="none" stroke="currentColor" stroke-width="2" ' +
    'stroke-linecap="round" stroke-linejoin="round"/></svg>';
  document.body.appendChild(toTop);

  const updateToTop = () => {
    toTop.classList.toggle('visible', window.scrollY > Math.max(600, window.innerHeight));
  };
  window.addEventListener('scroll', updateToTop, { passive: true });
  window.addEventListener('resize', updateToTop);
  updateToTop();

  toTop.addEventListener('click', () => {
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    window.scrollTo({ top: 0, behavior: reduceMotion ? 'instant' : 'smooth' });
    // Keyboard users continue from the top of the page, not from the hidden button.
    document.querySelector('header a')?.focus({ preventScroll: true });
  });

  // Pause button for the scrolling hero sign (moving content needs one,
  // WCAG 2.2.2). CSS shows it only while the sign scrolls.
  const sign = document.querySelector('.led-scroll')?.closest('.led-sign');
  if (sign) {
    const pause = document.createElement('button');
    pause.type = 'button';
    pause.className = 'led-pause';
    const icons = {
      pause: '<rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/>',
      play: '<path d="M8 5.5v13a1 1 0 0 0 1.5.86l10-6.5a1 1 0 0 0 0-1.72l-10-6.5A1 1 0 0 0 8 5.5z"/>',
    };
    const show = (paused) => {
      sign.classList.toggle('paused', paused);
      pause.setAttribute('aria-label', paused ? 'Play the scrolling sign' : 'Pause the scrolling sign');
      pause.innerHTML =
        '<svg viewBox="0 0 24 24" width="12" height="12" fill="currentColor" aria-hidden="true">' +
        (paused ? icons.play : icons.pause) +
        '</svg>';
    };
    show(false);
    pause.addEventListener('click', () => show(!sign.classList.contains('paused')));
    sign.appendChild(pause);
  }

  // FAQ search filter (faq.html only)
  const search = document.getElementById('faq-search');
  if (!search) return;

  const groups = Array.from(document.querySelectorAll('.faq-group'));
  const items = Array.from(document.querySelectorAll('.faq-item'));
  const empty = document.getElementById('faq-empty');

  search.addEventListener('input', () => {
    const query = search.value.trim().toLowerCase();
    let anyVisible = false;

    groups.forEach((group) => {
      let groupHasMatch = false;
      group.querySelectorAll('.faq-item').forEach((item) => {
        const text = item.textContent.toLowerCase();
        const matches = query === '' || text.includes(query);
        item.hidden = !matches;
        if (matches) {
          groupHasMatch = true;
          anyVisible = true;
          if (query !== '') item.open = true;
        } else {
          item.open = false;
        }
      });
      group.hidden = !groupHasMatch;
    });

    if (empty) empty.style.display = anyVisible ? 'none' : 'block';
  });
});
