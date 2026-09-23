//
//  ChatGPTScripts.swift
//
//  Created by Grant Brooks Goodman.
//  Copyright © NEOTechnica Corporation. All rights reserved.
//

/* Native */
import Foundation

/// Scripts injected at document start, for the main frame only, that
/// suppress permission prompts, keep the page reporting itself as
/// visible, and speed up its initial load.
enum ChatGPTScripts {
    // MARK: - Properties

    /// Reports common permission queries as denied so the page never
    /// prompts for notifications, location, camera, etc.
    static let denyPermissions = """
    (function(){
      // Notifications
      try { Notification.requestPermission = () => Promise.resolve('denied'); } catch {}
      Object.defineProperty(Notification, 'permission', { get: ()=>'denied' });

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
    """

    /// Forces the document to report itself as visible, so WebKit does
    /// not throttle the tab (and any mid-stream work) as a background one.
    static let fauxVisibility = """
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
    """

    /// Makes `requestIdleCallback` run almost immediately with a large
    /// budget, so the single-page app boots faster.
    static let promoteIdleCallback = """
    (function(){
      // Make requestIdleCallback run ASAP with a large budget
      window.requestIdleCallback = function(callback){
        return setTimeout(() => callback({
          didTimeout: false,
          timeRemaining: function(){ return 50; } // ~3 frames of work
        }), 0);
      };
      window.cancelIdleCallback = function(timeoutID){ clearTimeout(timeoutID); };
    })();
    """

    /// Every script injected at document start, for the main frame only.
    static let documentStartScripts: [String] = [
        denyPermissions,
        fauxVisibility,
        promoteIdleCallback,
    ]
}
