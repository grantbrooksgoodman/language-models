// Injected at document start, for the main frame only. Makes
// `requestIdleCallback` run almost immediately with a large budget, so
// the single-page app boots faster.
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
