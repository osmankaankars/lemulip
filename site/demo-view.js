/* The real Mac recording shares the existing demo stage; no automatic playback. */
(function (root, factory) {
  'use strict';
  if (typeof module === 'object' && module.exports) module.exports = factory;
  else factory(root.document);
})(typeof window === 'undefined' ? globalThis : window, function initialize(doc) {
  'use strict';
  const get = id => doc.getElementById(id);
  const button = get('watch-native'), stage = get('demo-stage');
  const illustration = get('desktop-demo'), layer = get('native-recording');
  const video = get('native-video'), controls = get('demo-controls');
  const note = get('demo-source'), error = get('native-error');
  if (!button || !stage || !illustration || !layer || !video || !controls || !note || !error) return;
  let watching = false;

  function show(watch, restoreFocus = false) {
    watching = watch;
    if (watch) doc.dispatchEvent(new CustomEvent('lemulip:watch-native'));
    else video.pause();
    stage.classList.toggle('watching-native', watch);
    illustration.inert = watch;
    controls.inert = watch;
    illustration.setAttribute('aria-hidden', String(watch));
    controls.setAttribute('aria-hidden', String(watch));
    controls.style && (controls.style.visibility = watch ? 'hidden' : '');
    layer.hidden = !watch;
    button.setAttribute('aria-pressed', String(watch));
    button.textContent = watch ? 'Back To The Wheel' : 'Watch On A Mac';
    note.textContent = watch ? 'Recorded In Lemulip. Finder To Finished File.' : 'Browser Simulation. No Uploads.';
    if (watch) {
      video.focus({ preventScroll: true });
      // A rejected playback request leaves the native Play control available.
      const attempt = video.play();
      if (attempt && typeof attempt.catch === 'function') attempt.catch(() => {});
    } else if (restoreFocus) button.focus({ preventScroll: true });
  }
  button.hidden = false;
  layer.hidden = true;
  button.setAttribute('aria-pressed', 'false');
  button.addEventListener('click', () => show(!watching));
  for (const name of ['origin-desktop', 'origin-finder']) {
    get(name)?.addEventListener('click', () => { if (watching) show(false); });
  }
  stage.addEventListener('keydown', event => {
    if (event.key === 'Escape' && watching && !doc.fullscreenElement) {
      event.preventDefault(); show(false, true);
    }
  });
  doc.addEventListener('visibilitychange', () => { if (doc.hidden) video.pause(); });
  video.addEventListener('error', () => { error.hidden = false; });
});
