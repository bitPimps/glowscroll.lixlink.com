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
      link.addEventListener('click', () => links.classList.remove('open'));
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
    window.scrollTo({ top: 0, behavior: reduceMotion ? 'auto' : 'smooth' });
    // Keyboard users continue from the top of the page, not from the hidden button.
    document.querySelector('header a')?.focus({ preventScroll: true });
  });

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
