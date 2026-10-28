// Injected at document start, for the main frame only. Forces the
// document to report itself as visible, so WebKit does not throttle
// the tab (and any mid-stream work) as a background one.
(function(){
  try {
    // Force visible state
    Object.defineProperty(document, 'hidden', { get: () => false });
    Object.defineProperty(document, 'visibilityState', { get: () => 'visible' });
    // Legacy webkitHidden alias (if present)
    if ('webkitHidden' in document) {
      Object.defineProperty(document, 'webkitHidden', { get: () => false });
    }
    // Fire a visibilitychange to update any listeners
    setTimeout(() => {
      document.dispatchEvent(new Event('visibilitychange'));
      window.dispatchEvent(new Event('pageshow'));
    }, 0);

    // Nudge “good network / no data saver”
    if (navigator && navigator.connection) {
      try {
        Object.defineProperty(navigator.connection, 'saveData', { get: () => false });
        Object.defineProperty(navigator.connection, 'effectiveType', { get: () => '4g' });
      } catch {}
    }
  } catch {}
})();
