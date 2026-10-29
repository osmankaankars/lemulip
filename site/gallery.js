/* Native app screenshots. Deliberately manual: this is not a second demo. */
(() => {
  'use strict';
  const gallery = document.getElementById('app-gallery');
  if (!gallery) return;
  const slides = Array.from(gallery.querySelectorAll('.app-slide'));
  const tabs = Array.from(gallery.querySelectorAll('[data-screen]'));
  const captionTitle = document.getElementById('gallery-caption-title');
  const description = document.getElementById('gallery-description');
  let selected = 0;
  function show(index, moveFocus = false) {
    selected = (index + slides.length) % slides.length;
    slides.forEach((slide, i) => { slide.hidden = i !== selected; });
    tabs.forEach((tab, i) => {
      tab.setAttribute('aria-selected', String(i === selected));
      tab.tabIndex = i === selected ? 0 : -1;
    });
    captionTitle.textContent = tabs[selected].dataset.title;
    description.textContent = tabs[selected].dataset.description;
    if (moveFocus) tabs[selected].focus({ preventScroll: true });
  }
  tabs.forEach((tab, i) => {
    tab.addEventListener('click', () => show(i));
    tab.addEventListener('keydown', event => {
      let next;
      if (event.key === 'ArrowRight') next = selected + 1;
      else if (event.key === 'ArrowLeft') next = selected - 1;
      else if (event.key === 'Home') next = 0;
      else if (event.key === 'End') next = slides.length - 1;
      else return;
      event.preventDefault(); event.stopPropagation(); show(next, true);
    });
  });
  gallery.querySelector('.gallery-tabs').hidden = false;
  show(0);
})();
