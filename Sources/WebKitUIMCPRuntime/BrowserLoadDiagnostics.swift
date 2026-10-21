import Foundation

/// Bounded structural diagnostics: never console strings, URLs, request bodies or field values.
public struct BrowserLoadDiagnostics: Codable, Sendable {
  public let documentReadyState: String
  public let visibilityState: String
  public let hasBody: Bool
  public let sampledScripts: Int
  public let parserBlockingScripts: Int
  public let sampledResources: Int
  public let resourceTimingTruncated: Bool
  public let httpErrorResponses: Int
  public let responseStatusAvailable: Bool
  public let scriptErrors: Int
  public let unhandledRejections: Int
  public let resourceErrors: [String: Int]
}

enum BrowserLoadDiagnosticScripts {
  static let bootstrap = #"""
    (() => {
      const state = { scriptErrors: 0, unhandledRejections: 0,
        resourceErrors: {script:0,link:0,img:0,iframe:0,other:0} };
      globalThis.__webkituiLoadDiagnostics = state;
      const increment = (object, key) => object[key] = Math.min(255, object[key] + 1);
      addEventListener('error', event => {
        const target = event.target;
        if (target && target !== window && target.nodeType === 1) {
          const tag = String(target.localName || '').toLowerCase();
          increment(state.resourceErrors, ['script','link','img','iframe'].includes(tag) ? tag : 'other');
        } else increment(state, 'scriptErrors');
      }, true);
      addEventListener('unhandledrejection', () => increment(state, 'unhandledRejections'));
    })();
    """#

  static let snapshot = #"""
    const state = globalThis.__webkituiLoadDiagnostics;
    const scripts = document.scripts;
    let parserBlocking = 0;
    for (let i = 0; i < Math.min(scripts.length, 256); i++) {
      const script = scripts[i];
      const classic = !script.type || ['text/javascript','application/javascript'].includes(script.type.toLowerCase());
      if (classic && script.src && !script.async && !script.defer) parserBlocking++;
    }
    const resources = performance.getEntriesByType('resource');
    const sample = resources.slice(0, 256);
    return JSON.stringify({
      documentReadyState: ['loading','interactive','complete'].includes(document.readyState) ? document.readyState : 'unknown',
      visibilityState: ['visible','hidden','prerender'].includes(document.visibilityState) ? document.visibilityState : 'unknown',
      hasBody: !!document.body, sampledScripts: Math.min(scripts.length, 256),
      parserBlockingScripts: parserBlocking, sampledResources: sample.length,
      resourceTimingTruncated: resources.length > 256,
      httpErrorResponses: sample.filter(entry => Number.isFinite(entry.responseStatus) && entry.responseStatus >= 400 && entry.responseStatus <= 599).length,
      responseStatusAvailable: sample.some(entry => typeof entry.responseStatus === 'number'),
      scriptErrors: state?.scriptErrors ?? 0, unhandledRejections: state?.unhandledRejections ?? 0,
      resourceErrors: state?.resourceErrors ?? {script:0,link:0,img:0,iframe:0,other:0}
    });
    """#
}
