/*
 * fullscreen.js — press `f` to read a lesson full-screen.
 *
 * Canonical source: dotfiles claude/.claude/templates/teach/fullscreen.js.
 * Copied into each teaching workspace's assets/ by `teach-fullscreen`; edit the
 * template, not the copies, then re-run the script to propagate.
 *
 * Self-contained by design. Workspaces name their stylesheet differently
 * (style.css, lesson.css, course.css, theme.css, deck.css), so this ships its
 * own <style> rather than assuming a file to append to. One <script> tag is the
 * whole integration.
 */
(function () {
  'use strict';

  // Including this twice must not double-bind the key: two handlers would enter
  // fullscreen and leave it again on the same keypress.
  if (window.__teachFullscreen) return;
  window.__teachFullscreen = true;

  var HINT_SEEN_KEY = 'teach:fullscreen-hint-seen';
  var ZOOM = 1.15;

  /*
   * Type scales via `zoom` rather than a font-size override. The workspaces size
   * text inconsistently — tmux pins `body { font-size: 19px }` with rem children,
   * sar pins `html { font-size: 18px }` — so no single font-size rule enlarges
   * both correctly, while zoom scales px, rem and em alike.
   */
  var style = document.createElement('style');
  style.textContent = [
    'html:fullscreen { zoom: ' + ZOOM + '; }',
    /* Fullscreening <html> paints an unstyled backdrop behind the body's own
     * background — black in most browsers. The real colour is copied from the
     * body at runtime (see syncBackdrop) since every workspace has its own theme. */
    'html:fullscreen::backdrop { background: var(--teach-fs-backdrop, Canvas); }',
    'html:fullscreen { background: var(--teach-fs-backdrop, Canvas); }',
    '.teach-fs-hint {',
    '  position: fixed; inset-block-end: 1rem; inset-inline-end: 1rem; z-index: 2147483647;',
    '  font: 500 12px/1 ui-sans-serif, -apple-system, system-ui, sans-serif;',
    '  letter-spacing: 0.04em; color: #fff; background: rgba(0, 0, 0, 0.55);',
    '  padding: 0.5em 0.85em; border-radius: 999px; pointer-events: none;',
    '  opacity: 0; transition: opacity 0.4s ease; backdrop-filter: blur(4px);',
    '}',
    '.teach-fs-hint[data-visible] { opacity: 0.72; }',
    '.teach-fs-hint kbd {',
    '  font: inherit; font-weight: 700; background: rgba(255, 255, 255, 0.22);',
    '  border-radius: 4px; padding: 0.1em 0.4em; margin: 0 0.15em;',
    '}',
    /* Reference docs are built to print; neither the hint nor the zoom belongs
     * on paper. `:fullscreen` never matches while printing, so only the hint
     * needs excluding explicitly. */
    '@media print { .teach-fs-hint { display: none !important; } }',
    '@media (prefers-reduced-motion: reduce) { .teach-fs-hint { transition: none; } }'
  ].join('\n');
  document.head.appendChild(style);

  function isFullscreen() {
    return !!(document.fullscreenElement || document.webkitFullscreenElement);
  }

  function syncBackdrop() {
    // Read the body's real background so the fullscreen backdrop matches the
    // workspace's theme instead of falling back to black.
    var bg = getComputedStyle(document.body).backgroundColor;
    if (bg && bg !== 'transparent' && bg !== 'rgba(0, 0, 0, 0)') {
      document.documentElement.style.setProperty('--teach-fs-backdrop', bg);
    }
  }

  function toggle() {
    if (isFullscreen()) {
      (document.exitFullscreen || document.webkitExitFullscreen).call(document);
      return;
    }
    syncBackdrop();
    var el = document.documentElement;
    var request = el.requestFullscreen || el.webkitRequestFullscreen;
    // Rejects when the gesture isn't trusted or the document is framed; a lesson
    // that can't go fullscreen should still read normally.
    var result = request.call(el);
    if (result && result.catch) result.catch(function () {});
  }

  /*
   * `f` is a letter, so the binding has to stay out of the way of typing. The
   * quiz and drill widgets across these workspaces read from inputs, and Cmd-F
   * is the browser's find.
   */
  function shouldIgnore(e) {
    if (e.defaultPrevented || e.repeat) return true;
    if (e.metaKey || e.ctrlKey || e.altKey) return true;
    var el = e.target;
    if (!el) return false;
    if (el.isContentEditable) return true;
    return /^(INPUT|TEXTAREA|SELECT|BUTTON|OPTION)$/.test(el.tagName);
  }

  document.addEventListener('keydown', function (e) {
    if (e.key !== 'f' && e.key !== 'F') return;
    if (shouldIgnore(e)) return;
    if (!document.fullscreenEnabled && !document.webkitFullscreenEnabled) return;
    e.preventDefault();
    toggle();
    dismissHint();
  });

  /*
   * A keybinding nobody can see is a keybinding nobody uses — but only until
   * it's learned, so the hint retires itself after the first successful toggle.
   */
  var hint = null;

  function dismissHint() {
    try { localStorage.setItem(HINT_SEEN_KEY, '1'); } catch (err) {}
    if (!hint) return;
    hint.removeAttribute('data-visible');
    var node = hint;
    hint = null;
    setTimeout(function () { node.remove(); }, 500);
  }

  function showHint() {
    var seen;
    try { seen = localStorage.getItem(HINT_SEEN_KEY); } catch (err) { seen = '1'; }
    if (seen) return;
    if (!document.fullscreenEnabled && !document.webkitFullscreenEnabled) return;

    hint = document.createElement('div');
    hint.className = 'teach-fs-hint';
    hint.innerHTML = 'press <kbd>f</kbd> for fullscreen';
    document.body.appendChild(hint);
    requestAnimationFrame(function () {
      if (hint) hint.setAttribute('data-visible', '');
    });
    setTimeout(function () {
      if (hint) hint.removeAttribute('data-visible');
    }, 6000);
  }

  function init() {
    syncBackdrop();
    showHint();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
