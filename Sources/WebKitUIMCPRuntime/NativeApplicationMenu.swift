import AppKit

@MainActor
public enum WebKitNativeApplicationMenu {
  public static func install(on application: NSApplication) {
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

    application.mainMenu = mainMenu
  }

  private static func commandItem(title: String, action: Selector, key: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = [.command]
    return item
  }
}
