/* Native app screenshots. Deliberately manual: this is not a second demo. */
(() => {
  'use strict';
  const gallery = document.getElementById('app-gallery');
  if (!gallery) return;
  const slides = Array.from(gallery.querySelectorAll('.app-slide'));
  const tabs = Array.from(gallery.querySelectorAll('[data-screen]'));
  const caption = document.getElementById('gallery-caption');
  const counter = document.getElementById('gallery-counter');
  let selected = 0;
  function show(index, moveFocus = false) {
    selected = (index + slides.length) % slides.length;
    slides.forEach((slide, i) => { slide.hidden = i !== selected; });
    tabs.forEach((tab, i) => {
      tab.setAttribute('aria-selected', String(i === selected));
      tab.tabIndex = i === selected ? 0 : -1;
    });
    caption.textContent = tabs[selected].textContent;
    counter.textContent = `${selected + 1} / ${slides.length}`;
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
  document.getElementById('gallery-next').addEventListener('click', () => show(selected + 1));
  document.getElementById('gallery-previous').addEventListener('click', () => show(selected - 1));
  gallery.querySelector('.gallery-tabs').hidden = false;
  gallery.querySelector('.gallery-navigation').hidden = false;
  show(0);
})();
