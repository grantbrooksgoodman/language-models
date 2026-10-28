// Injected at document start, for the main frame only. Reports common
// permission queries as denied so the page never prompts for
// notifications, location, camera, etc.
(function(){
  // Notifications
  try {
    if (window.Notification) {
      Notification.requestPermission = () => Promise.resolve('denied');
      Object.defineProperty(Notification, 'permission', { get: ()=>'denied' });
    }
  } catch {}

  // Generic permissions queries
  if (navigator && navigator.permissions && navigator.permissions.query) {
    const originalQuery = navigator.permissions.query.bind(navigator.permissions);
    navigator.permissions.query = (descriptor) => {
      if (!descriptor || !descriptor.name) return originalQuery(descriptor);
      // report the common ones as denied so pages don't enable extras
      if (['background-sync','camera','clipboard-read','geolocation','microphone','notifications'].includes(descriptor.name)) {
        return Promise.resolve({ state:'denied' });
      }
      return originalQuery(descriptor);
    };
  }
})();
