/// Shared observation/dispatch measurements; site metadata is not authorization.
enum BrowserInputCapabilities {
  static let source = #"""
    const measuredFillCapability = element => {
      if (privacyIsSensitive(element) || element.type === 'password') return 'sensitive';
      const nativeText = element.localName === 'textarea'
        || (element.localName === 'input'
          && ['text','search','email','tel','url','number','password',
              'date','datetime-local','time','month','week'].includes(element.type));
      if (!nativeText && !element.isContentEditable) return 'unsupported';
      if (element.matches(':disabled') || element.getAttribute('aria-disabled') === 'true') return 'disabled';
      if (element.readOnly || element.getAttribute('aria-readonly') === 'true') return 'readonly';
      return 'editable';
    };
    """#
}
