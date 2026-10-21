enum BrowserScrollGeometry {
  static let source = #"""
    const isScrollableContainer = element => {
      if (element === element.ownerDocument?.body || element === element.ownerDocument?.documentElement) return false;
      const style = element.ownerDocument.defaultView.getComputedStyle(element);
      return (['auto','scroll','overlay'].includes(style.overflowY)
          && element.scrollHeight > element.clientHeight + 1)
        || (['auto','scroll','overlay'].includes(style.overflowX)
          && element.scrollWidth > element.clientWidth + 1);
    };
    """#
}
