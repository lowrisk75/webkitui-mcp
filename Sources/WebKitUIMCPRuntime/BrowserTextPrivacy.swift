import Foundation

public struct WebKitPrivacyInventoryLimitDiagnostic: Codable, Sendable, Equatable {
  public let category: String
  public let limit: Int?
  public let observedCountAtLeast: Int?
}

/// Browser-local text filtering. Values collected here are never returned to Swift.
/// This covers recognized credential fields/configuration rows, not arbitrary images
/// or every possible secret embedded in otherwise unstructured site content.
enum BrowserTextPrivacy {
  static let source = #"""
    const privacyPlain = value => String(value ?? '').normalize('NFC').replace(/\s+/g, ' ').trim();
    const privacyCredential = /(?:token|secret|password|passcode|credential|api[-_ ]?key|private[-_ ]?key|client[-_ ]?key|recovery[-_ ]?code|one[-_ ]?time|otp)/i;
    // An exact public name is not a token value. This narrow exception cannot
    // suppress conflicting credential metadata, password/autocomplete or opacity.
    const privacyPublicNameTerm = value => /^(?:(?:api|access)[ _-]*)?token[ _-]*name$/i.test(privacyPlain(value));
    const privacyOpaqueValue = value => {
      const text = String(value ?? '');
      if (/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(text)) return true;
      return text.length >= 32 && !/\s/.test(text)
        && /^[A-Za-z0-9._~+/=-]+$/.test(text) && new Set(text).size >= 12;
    };
    const privacyPublicTokenName = field => {
      if (field.localName !== 'input' || field.type !== 'text'
          || privacyPlain(field.getAttribute('autocomplete'))
          || privacyOpaqueValue(field.value)) return false;
      const labels = [field.getAttribute('aria-label'),
        ...Array.from(field.labels || []).map(label => label.textContent)];
      for (const id of privacyPlain(field.getAttribute('aria-labelledby')).split(' ').filter(Boolean)) {
        const root = field.getRootNode();
        const label = root.getElementById?.(id);
        if (!label) return false;
        labels.push(label.textContent);
      }
      const named = labels.map(privacyPlain).filter(Boolean);
      if (!named.length || !named.every(privacyPublicNameTerm)) return false;
      const metadata = ['id','name','aria-label','title','placeholder'].map(
        key => privacyPlain(field.getAttribute(key)));
      return metadata.every(value => privacyPublicNameTerm(value)
        || !/(token|state|csrf|nonce|session|assertion|secret|password|passcode|credential|otp|one[-_ ]?time|api[-_ ]?key|recovery[-_ ]?code|backup[-_ ]?code|private[-_ ]?key|seed[-_ ]?phrase)/i.test(value));
    };
    const privacyKey = value => {
      const key = privacyPlain(value);
      return key.length <= 128 && privacyCredential.test(key)
        && (/^[A-Z][A-Z0-9_]{2,100}$/.test(key)
          || /^(api|access|client|private|recovery|backup)?[ _-]*(token|key|secret|password|passcode|credentials?)$/i.test(key));
    };
    const privacyValues = new Set();
    const privacySensitiveNodes = new WeakSet();
    let privacyBudget = 0;
    const privacyRemember = value => {
      for (const text of [String(value ?? '').normalize('NFC'), privacyPlain(value)]) {
        if (!text || privacyValues.has(text)) continue;
        privacyBudget += text.length;
        if (privacyValues.size >= 256) {
          throw new Error('privacy_scan_limit_exceeded:values');
        }
        if (privacyBudget > 65536) {
          throw new Error('privacy_scan_limit_exceeded:characters');
        }
        privacyValues.add(text);
      }
    };
    const privacyRememberNode = node => {
      privacySensitiveNodes.add(node);
      privacyRemember(node.innerText);
      privacyRemember(node.textContent);
      for (const child of [node, ...node.querySelectorAll('*')]) {
        privacyRemember(child.getAttribute('aria-label'));
        privacyRemember(child.getAttribute('title'));
        for (const text of child.childNodes) {
          if (text.nodeType === Node.TEXT_NODE) privacyRemember(text.textContent.trim());
        }
      }
    };
    const privacyRoots = [document];
    const privacySeen = new Set(privacyRoots);
    let privacyNodeCount = 0;
    for (let rootIndex = 0; rootIndex < privacyRoots.length; rootIndex++) {
      const root = privacyRoots[rootIndex];
      // Count before collecting selector results. A shared node budget bounds
      // many small web components as well as a single enormous light DOM.
      const walker = (root.ownerDocument || root).createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
      for (let host = walker.nextNode(); host; host = walker.nextNode()) {
        if (++privacyNodeCount > 20000) throw new Error('privacy_scan_limit_exceeded:nodes');
        const nested = [host.shadowRoot];
        if (host.localName === 'iframe' || host.localName === 'frame') {
          try { nested.push(host.contentDocument); } catch (_) { /* opaque foreign frame */ }
        }
        for (const next of nested) if (next && !privacySeen.has(next)) {
          if (privacyRoots.length >= 512) throw new Error('privacy_scan_limit_exceeded:roots');
          privacySeen.add(next); privacyRoots.push(next);
        }
      }
      for (const field of root.querySelectorAll('input,textarea,[contenteditable]')) {
        if (field.localName === 'input' && ['checkbox','radio','submit','reset','button','image','range','color','file'].includes(field.type)) continue;
        const metadata = ['id','name','type','autocomplete','aria-label'].map(
          key => field.getAttribute(key) || '').join(' ');
        if (privacyCredential.test(metadata) && !privacyPublicTokenName(field)) {
          privacySensitiveNodes.add(field);
          privacyRemember(typeof field.value === 'string' ? field.value : field.textContent);
        }
      }
      for (const form of root.querySelectorAll('form,[role="form"]')) {
        const fields = Array.from(form.querySelectorAll('input,textarea,[contenteditable]'));
        if (!fields.some(field => privacyKey(field.value))) continue;
        for (const field of fields) {
          const label = ['id','name','aria-label'].map(key => field.getAttribute(key) || '').join(' ');
          if (/(^|[^a-z])(value|valeur)([^a-z]|$)/i.test(label)) {
            privacySensitiveNodes.add(field);
            privacyRemember(typeof field.value === 'string' ? field.value : field.textContent);
          }
        }
      }
      for (const row of root.querySelectorAll('tr,[role="row"],div,section,article,dt')) {
        if (row.localName === 'dt') {
          if (privacyKey(row.textContent) && row.nextElementSibling?.localName === 'dd') {
            privacyRememberNode(row.nextElementSibling);
          }
          continue;
        }
        const cells = Array.from(row.children);
        if (cells.length < 2 || cells.length > 16) continue;
        const structured = row.localName === 'tr' || row.getAttribute('role') === 'row';
        const keyIndex = cells.findIndex(cell => {
          const key = privacyPlain(cell.innerText);
          return privacyKey(key)
            && (structured || /^[A-Z][A-Z0-9_]{2,100}$/.test(key));
        });
        if (keyIndex < 0) continue;
        const table = row.closest('table,[role="table"],[role="grid"]');
        const headers = table ? Array.from(table.querySelectorAll('thead th,[role="columnheader"]')) : [];
        for (let index = 0; index < cells.length; index++) {
          if (index === keyIndex) continue;
          const cell = cells[index], text = privacyPlain(cell.innerText);
          if (/^(type|kind|genre)$/i.test(privacyPlain(headers[index]?.innerText))) continue;
          // Standalone action labels are public controls, not the value column.
          const buttons = cell.querySelectorAll('button,a,[role="button"]');
          if (buttons.length === 1 && privacyPlain(buttons[0].innerText) === text
              && /^(edit|modifier|delete|supprimer|copy|copier)(\s+(setting|configuration|variable|secret))?$/i.test(text)) continue;
          if (text) privacyRememberNode(cell);
        }
      }
    }
    // Encode every UTF-16 unit as a literal escape: site text never becomes regex
    // syntax. A single replacement pass cannot recursively redact its own marker.
    const privacyPattern = privacyValues.size ? new RegExp(
      Array.from(privacyValues).sort((a,b) => b.length - a.length).map(value =>
        value.split('').map(unit => '\\u' + unit.charCodeAt(0).toString(16).padStart(4,'0')).join('')
      ).join('|'), 'g') : null;
    const privacyRedact = value => {
      const text = String(value ?? '').normalize('NFC');
      return privacyPattern ? text.replace(privacyPattern, '[redacted]') : text;
    };
    const privacyIsSensitive = node => {
      for (let cursor = node; cursor; cursor = cursor.parentElement || cursor.getRootNode?.()?.host || null) {
        if (privacySensitiveNodes.has(cursor)) return true;
      }
      return false;
    };
    const privacyJSONStringify = value => JSON.stringify(value,
      (_, field) => typeof field === 'string' ? privacyRedact(field) : field);
    """#
}
