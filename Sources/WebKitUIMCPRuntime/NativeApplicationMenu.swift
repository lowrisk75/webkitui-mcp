import AppKit

@MainActor
public enum WebKitNativeApplicationMenu {
  /// The characters this menu claims as ⌘ key equivalents, lowercased.
  ///
  /// A key event carrying ⌘ is offered to a menu before the content of the key window
  /// sees it, and one of these is Quit: a keystroke a confirmation described as reaching
  /// the page would end this process instead. The native key dispatcher refuses these
  /// chords rather than send one whose effect it cannot honestly describe. Compared
  /// case-insensitively, because AppKit matches a key equivalent against the character
  /// the key produces unshifted, so ⇧⌘Z is the same claim as ⌘Z.
  ///
  /// A test asserts this is exactly what `mainMenu()` installs, because the menu is the
  /// thing a later edit will change. Not main-actor isolated: the key catalogue and the
  /// MCP server both refuse a chord from this set, and neither of them is a menu.
  public nonisolated static let commandKeyEquivalents: Set<Character> = [
    "q", "z", "x", "c", "v", "a",
  ]

  public static func install(on application: NSApplication) {
    application.mainMenu = mainMenu()
  }

  public static func mainMenu() -> NSMenu {
    let mainMenu = NSMenu(title: "Main")

    let applicationItem = NSMenuItem()
    let applicationMenu = NSMenu(title: "WebkitUIMCP")
    applicationMenu.addItem(
      withTitle: "Quit WebkitUIMCP",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    applicationItem.submenu = applicationMenu
    mainMenu.addItem(applicationItem)

    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.autoenablesItems = true
    editMenu.addItem(commandItem(title: "Undo", action: Selector(("undo:")), key: "z"))
    let redo = commandItem(title: "Redo", action: Selector(("redo:")), key: "Z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(redo)
    editMenu.addItem(.separator())
    editMenu.addItem(commandItem(title: "Cut", action: #selector(NSText.cut(_:)), key: "x"))
    editMenu.addItem(commandItem(title: "Copy", action: #selector(NSText.copy(_:)), key: "c"))
    editMenu.addItem(commandItem(title: "Paste", action: #selector(NSText.paste(_:)), key: "v"))
    editMenu.addItem(.separator())
    editMenu.addItem(
      commandItem(title: "Select All", action: #selector(NSText.selectAll(_:)), key: "a")
    )
    editItem.submenu = editMenu
    mainMenu.addItem(editItem)

    return mainMenu
  }

  private static func commandItem(title: String, action: Selector, key: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = [.command]
    return item
  }
}
