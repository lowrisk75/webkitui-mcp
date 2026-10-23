import Foundation

/// The structure around a visible label, without any of the page's content: which tags
/// and roles wrap the text, whether they are focusable, what the cursor is. This is
/// what a collector fix needs and what a page's text is not. Values of attributes are
/// never read; only their names. The label itself is the one the person typed.
public struct BrowserDOMShape: Codable, Equatable, Sendable {
  public struct Node: Codable, Equatable, Sendable {
    public let tag: String
    public let role: String?
    public let hasHref: Bool
    public let hasTabIndex: Bool
    public let hasOnClick: Bool
    public let cursor: String
    public let display: String
    public let ariaHidden: Bool
    public let isShadowHost: Bool
    public let insideShadowRoot: Bool
    /// Attribute names, sorted, at most 20. Never values.
    public let attributeNames: [String]
    /// Kept empty for schema compatibility. CSS class values are never exported.
    public let classTokens: [String]
  }

  public struct Match: Codable, Equatable, Sendable {
    /// The matched element, then its ancestors nearest first, at most six.
    public let chain: [Node]
    public let depth: Int
    public let textLength: Int
  }

  public let label: String
  public let matchCount: Int
  public let matches: [Match]
  public let truncated: Bool
}

enum BrowserDOMShapeScripts {
  /// Argument `label`: the exact visible text to look for, whitespace-collapsed,
  /// compared case-insensitively. Returns JSON for `BrowserDOMShape`.
  static let collect =
    BrowserTextPrivacy.source + #"""
      const collapse = value => String(value ?? '').replace(/\s+/g, ' ').trim();
      const wanted = collapse(label).toLowerCase();
      const composedParent = element =>
        element?.parentElement || element?.getRootNode?.()?.host || null;
      const roots = [document];
      const all = [];
      for (let index = 0; index < roots.length; index += 1) {
        const root = roots[index];
        const walker = (root.ownerDocument || root).createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
        for (let candidate = walker.nextNode(); candidate; candidate = walker.nextNode()) {
          if (all.length >= 20000) throw new Error('privacy_scan_limit_exceeded:nodes');
          all.push(candidate);
          if (candidate.shadowRoot) {
            if (roots.length >= 512) throw new Error('privacy_scan_limit_exceeded:roots');
            roots.push(candidate.shadowRoot);
          }
        }
      }
      // Arbitrary attribute names, custom tags, roles and CSS classes can all
      // carry site data. Export only fixed vocabulary and presence booleans.
      const tags = new Set('html body main section article div span p label a button input textarea select option form fieldset legend h1 h2 h3 h4 h5 h6 dialog ul ol li table tr th td summary details header footer nav aside strong em small'.split(' '));
      const roles = new Set('button link textbox checkbox radio switch combobox listbox option dialog alertdialog region heading tab tablist tabpanel list listitem table row cell columnheader rowheader form group navigation main alert status'.split(' '));
      const attributes = new Set('id class style role href tabindex onclick aria-label aria-labelledby aria-describedby aria-hidden aria-modal aria-expanded aria-controls aria-disabled aria-selected aria-checked name type disabled readonly hidden inert contenteditable'.split(' '));
      const rendered = element => {
        if (privacyIsSensitive(element) || !element.getClientRects().length) return false;
        for (let cursor = element, depth = 0; cursor; cursor = composedParent(cursor)) {
          if (++depth > 256) throw new Error('dom_shape_depth_limit_exceeded');
          const style = cursor.ownerDocument.defaultView.getComputedStyle(cursor);
          if (style.display === 'none' || style.visibility !== 'visible' || Number(style.opacity) === 0
              || cursor.hidden || cursor.getAttribute('aria-hidden') === 'true' || cursor.hasAttribute('inert')) return false;
        }
        return true;
      };
      const describe = element => {
        const view = element.ownerDocument?.defaultView;
        let style = null;
        try { style = view?.getComputedStyle(element); } catch { style = null; }
        const names = Array.from(element.attributes ?? []).map(a => String(a.name).toLowerCase())
          .filter(name => attributes.has(name)).sort().slice(0, 20);
        const role = collapse(element.getAttribute?.('role')).toLowerCase();
        return {
          tag: tags.has(element.localName) ? element.localName : 'custom',
          role: roles.has(role) ? role : null,
          hasHref: element.hasAttribute?.('href') === true,
          hasTabIndex: element.hasAttribute?.('tabindex') === true,
          hasOnClick: element.hasAttribute?.('onclick') === true,
          cursor: style && ['auto','default','pointer','text','not-allowed'].includes(style.cursor) ? style.cursor : 'other',
          display: style && ['none','contents','block','inline','inline-block','flex','inline-flex','grid','inline-grid','table','table-row','table-cell','list-item'].includes(style.display) ? style.display : 'other',
          ariaHidden: collapse(element.getAttribute?.('aria-hidden')).toLowerCase() === 'true',
          isShadowHost: Boolean(element.shadowRoot),
          insideShadowRoot: element.getRootNode?.() instanceof ShadowRoot,
          attributeNames: names,
          classTokens: []
        };
      };
      const matches = [];
      let count = 0;
      if (wanted.length > 0) {
        for (const element of all) {
          if (['script', 'style', 'noscript', 'template'].includes(element.localName) || !rendered(element)) continue;
          const own = collapse(element.innerText ?? '').toLowerCase();
          if (own !== wanted) continue;
          // Keep the innermost element carrying exactly this text: a wrapper whose only
          // text is the same label is reported as an ancestor, not a second match.
          const innerSame = Array.from(element.children).some(child =>
            rendered(child) && collapse(child.innerText ?? '').toLowerCase() === wanted);
          if (innerSame) continue;
          count += 1;
          if (matches.length >= 5) continue;
          const chain = [];
          let depth = 0;
          for (let cursor = element; cursor && chain.length < 7; cursor = composedParent(cursor)) {
            chain.push(describe(cursor));
          }
          for (let cursor = element; cursor && depth < 256; cursor = composedParent(cursor)) depth += 1;
          matches.push({ chain, depth, textLength: own.length });
        }
      }
      return privacyJSONStringify({ label: collapse(label).slice(0, 200), matchCount: count, matches, truncated: count > matches.length });
      """#
}

extension WebKitRuntime {
  /// Collects `BrowserDOMShape` around every rendered element whose collapsed text
  /// equals `label`. Requires agent control like any other read.
  public func domShape(aroundLabel label: String) async throws -> BrowserDOMShape {
    try requireAgentControlForDiagnostics()
    let bounded = String(label.prefix(200))
    guard
      let json = try await webView.callAsyncJavaScript(
        BrowserDOMShapeScripts.collect, arguments: ["label": bounded], in: nil,
        contentWorld: diagnosticsContentWorld) as? String,
      let data = json.data(using: .utf8)
    else { throw WebKitRuntimeError.malformedInstrumentationResult }
    return try JSONDecoder().decode(BrowserDOMShape.self, from: data)
  }
}
