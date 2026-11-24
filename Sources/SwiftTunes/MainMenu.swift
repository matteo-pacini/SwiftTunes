import AppKit

/// The application's main menu: an app menu with Quit, and an Edit menu.
///
/// An accessory app never shows a menu bar, but AppKit still sends the
/// Command-key equivalents of the main menu's items down the responder
/// chain; without this menu, Command-V, Command-Z and the rest reach no text
/// field. The Edit items have no target, so they act on the first responder.
/// Quit has no key equivalent: it would stop a tune being made, and the
/// status item's menu already offers it.
func makeMainMenu() -> NSMenu {
    let main = NSMenu()

    let appMenu = NSMenu(title: "SwiftTunes")
    appMenu.addItem(NSMenuItem(title: "Quit SwiftTunes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    main.addItem(submenuItem(appMenu))

    let edit = NSMenu(title: "Edit")
    edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
    let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(redo)
    edit.addItem(.separator())
    edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    edit.addItem(NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
    edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    main.addItem(submenuItem(edit))

    return main
}

private func submenuItem(_ menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
    item.submenu = menu
    return item
}
