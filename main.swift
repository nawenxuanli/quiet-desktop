import SwiftUI
import AppKit
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

struct LaunchItem: Identifiable {
    let url: URL
    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

struct PhotoCrop: Codable {
    var zoom: Double = 1
    var x: Double = 0
    var y: Double = 0
}

final class DesktopModel: ObservableObject {
    @Published var apps: [LaunchItem] = []
    @Published var query = ""
    @Published var showApps = false
    @Published var editingFavorites = false
    @Published var favoriteIDs: [String] = []
    @Published var draftIDs: [String] = []
    @Published var editorQuery = ""
    @Published var error: String?
    @Published var photo: NSImage?
    @Published var selectedPhoto: PhotosPickerItem?
    @Published var crop = PhotoCrop()
    @Published var draftCrop = PhotoCrop()
    @Published var editingCrop = false
    init() {
        var found: [URL] = []
        for path in ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"] {
            if let contents = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
                found += contents.filter { $0.pathExtension == "app" }
            }
        }
        apps = Dictionary(grouping: found.map { LaunchItem(url: $0) }, by: { $0.name }).compactMap { $0.value.first }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        favoriteIDs = UserDefaults.standard.stringArray(forKey: "quietdesktop.favorites") ?? ["Safari", "Mail", "Calendar", "Notes", "Music", "System Settings"].compactMap { name in apps.first { $0.name == name }?.id }
        if let data = UserDefaults.standard.data(forKey: "quietdesktop.photo") { photo = NSImage(data: data) }
        if let data = UserDefaults.standard.data(forKey: "quietdesktop.crop"), let saved = try? JSONDecoder().decode(PhotoCrop.self, from: data) {
            crop = PhotoCrop(zoom: min(4, max(1, saved.zoom)), x: min(1, max(-1, saved.x)), y: min(1, max(-1, saved.y)))
        }
    }
    func beginCrop() { draftCrop = crop; editingCrop = true }
    func saveCrop() {
        crop = draftCrop
        UserDefaults.standard.set(try? JSONEncoder().encode(crop), forKey: "quietdesktop.crop")
        editingCrop = false
    }
    func setPhoto(_ data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary),
              let stored = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            error = "This image couldn’t be loaded. Try another photo."
            return
        }
        UserDefaults.standard.set(stored, forKey: "quietdesktop.photo")
        photo = NSImage(cgImage: image, size: .zero)
        crop = PhotoCrop()
        UserDefaults.standard.removeObject(forKey: "quietdesktop.crop")
    }
    func choosePhotoFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a photo"
        panel.message = "Choose an image to display beside your clock."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do { self.setPhoto(try Data(contentsOf: url)) }
            catch { self.error = "This photo couldn’t be read. Try choosing it again." }
        }
    }
    func removePhoto() {
        photo = nil
        selectedPhoto = nil
        UserDefaults.standard.removeObject(forKey: "quietdesktop.photo")
        crop = PhotoCrop()
        UserDefaults.standard.removeObject(forKey: "quietdesktop.crop")
    }
    var results: [LaunchItem] { apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var favorites: [LaunchItem] {
        favoriteIDs.compactMap { id in apps.first { $0.id == id } }
    }
    var draftFavorites: [LaunchItem] { draftIDs.compactMap { id in apps.first { $0.id == id } } }
    var editorResults: [LaunchItem] { apps.filter { editorQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(editorQuery) } }
    func beginEditing() {
        draftIDs = favorites.map(\.id)
        editorQuery = ""
        editingFavorites = true
    }
    func toggleFavorite(_ id: String) {
        if draftIDs.contains(id) { draftIDs.removeAll { $0 == id } } else { draftIDs.append(id) }
    }
    func moveFavorite(_ id: String, by offset: Int) {
        guard let index = draftIDs.firstIndex(of: id), draftIDs.indices.contains(index + offset) else { return }
        draftIDs.swapAt(index, index + offset)
    }
    func saveFavorites() {
        favoriteIDs = draftIDs
        UserDefaults.standard.set(favoriteIDs, forKey: "quietdesktop.favorites")
        editingFavorites = false
    }
    func open(_ url: URL) {
        if !NSWorkspace.shared.open(url) { error = "Couldn’t open \(url.deletingPathExtension().lastPathComponent)." }
    }
}

struct DesktopView: View {
    @StateObject private var model = DesktopModel()
    @AppStorage("quietdesktop.note") private var note = ""
    @AppStorage("quietdesktop.light") private var light = false
    @FocusState private var searchFocused: Bool
    private var ink: Color { light ? Color(red: 0.16, green: 0.18, blue: 0.17) : Color(red: 0.91, green: 0.92, blue: 0.88) }
    private var background: Color { light ? Color(red: 0.94, green: 0.94, blue: 0.90) : Color(red: 0.075, green: 0.09, blue: 0.085) }
    private var muted: Color { ink.opacity(0.48) }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        HStack(spacing: 10) {
                            Circle().fill(Color(red: 0.64, green: 0.73, blue: 0.55)).frame(width: 7, height: 7)
                            Text("QUIET DESKTOP").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2.5)
                        }
                        Spacer()
                        Button { light.toggle() } label: { Image(systemName: light ? "moon" : "sun.max") }.help("Switch appearance")
                        Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Toggle full screen · Control Command F")
                        Button { NSApp.hide(nil) } label: { Image(systemName: "rectangle.on.rectangle") }.help("Return to your usual desktop · Command H")
                    }.foregroundStyle(muted).buttonStyle(.plain).font(.system(size: 15)).padding(.bottom, 58)

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 32) {
                            clock(width: 470).frame(minWidth: 370, maxWidth: .infinity, alignment: .leading)
                            photoPanel.frame(width: 390)
                        }
                        VStack(alignment: .leading, spacing: 28) {
                            clock(width: 470)
                            photoPanel.frame(maxWidth: .infinity)
                        }
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(muted)
                        TextField("Find an app…", text: $model.query).textFieldStyle(.plain).focused($searchFocused)
                            .onSubmit { if let app = model.results.first { model.open(app.url) } }
                        if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(muted) }
                        Text("⌘ K").font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
                    }.padding(17).background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(ink.opacity(0.08))).padding(.top, 36)

                    if !model.query.isEmpty || model.showApps {
                        HStack { label("APPLICATIONS"); Spacer(); Button(model.showApps ? "Close" : "All apps") { model.showApps.toggle() }.buttonStyle(.plain).foregroundStyle(muted) }.padding(.top, 28)
                        if model.results.isEmpty { Text("No matching apps").foregroundStyle(muted).padding(.vertical, 24) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 16) {
                            ForEach(model.results) { app in appButton(app) }
                        }.padding(.top, 18)
                    } else {
                        HStack(spacing: 20) {
                            label("WITHIN REACH")
                            Spacer()
                            Button("Edit") { model.beginEditing() }.help("Choose and arrange your apps")
                            Button("All apps ↗") { model.showApps = true }
                        }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(muted).padding(.top, 34)
                        if model.favorites.isEmpty {
                            Button("Add your favorite apps") { model.beginEditing() }.buttonStyle(.plain).foregroundStyle(muted).padding(.top, 22)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 14) {
                            ForEach(model.favorites) { app in appButton(app) }
                        }.padding(.top, 22)
                        Rectangle().fill(ink.opacity(0.10)).frame(height: 1).padding(.vertical, 32)
                        HStack(alignment: .top, spacing: 40) {
                            VStack(alignment: .leading, spacing: 18) {
                                label("YOUR SPACES")
                                folder("Home", symbol: "house", url: FileManager.default.homeDirectoryForCurrentUser)
                                folder("Documents", symbol: "doc", url: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
                                folder("Downloads", symbol: "arrow.down.to.line", url: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
                                folder("Desktop", symbol: "rectangle", url: FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0])
                            }.frame(width: 180, alignment: .leading)
                            VStack(alignment: .leading, spacing: 14) {
                                label("A LITTLE SPACE TO THINK")
                                ZStack(alignment: .topLeading) {
                                    if note.isEmpty { Text("What matters today?").foregroundStyle(muted).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                                    TextEditor(text: $note).font(.system(size: 14)).scrollContentBackground(.hidden).frame(minHeight: 110).accessibilityLabel("Notes, saved automatically on this Mac")
                                }
                                Text("Saved on this Mac").font(.system(size: 10)).foregroundStyle(muted)
                            }
                        }
                    }
                    Spacer(minLength: 34)
                    HStack { Text("Less noise. More room."); Spacer(); Text("⌘ H  Desktop    ·    ⌘ Q  Quit") }.font(.system(size: 10, design: .monospaced)).foregroundStyle(muted.opacity(0.7)).padding(.top, 28)
                }.padding(.horizontal, geometry.size.width < 800 ? 36 : 72).padding(.top, 38).padding(.bottom, 28).frame(maxWidth: 1080).frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
            }.background(background).foregroundStyle(ink)
        }
        .preferredColorScheme(light ? .light : .dark)
        .frame(minWidth: 680, minHeight: 650)
        .sheet(isPresented: $model.editingFavorites) {
            FavoritesEditor(model: model)
                .preferredColorScheme(light ? .light : .dark)
        }
        .sheet(isPresented: $model.editingCrop) {
            PhotoCropEditor(model: model).preferredColorScheme(light ? .light : .dark)
        }
        .background(Button("") { searchFocused = true }.keyboardShortcut("k", modifiers: .command).hidden())
        .onChange(of: model.selectedPhoto) { _, selection in
            guard let selection else { return }
            Task { @MainActor in
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self) else {
                        model.error = "This photo couldn’t be loaded. Try choosing a file instead."
                        model.selectedPhoto = nil
                        return
                    }
                    model.setPhoto(data)
                } catch { model.error = "This photo couldn’t be loaded. Try choosing a file instead." }
                model.selectedPhoto = nil
            }
        }
        .alert("Unable to complete action", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    func clock(width: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day()).font(.system(size: 13)).foregroundStyle(muted)
                Text(context.date, style: .time).font(.system(size: 85, weight: .ultraLight)).monospacedDigit().tracking(-4).lineLimit(1).minimumScaleFactor(0.65)
                Text(greeting(context.date)).font(.system(size: 17, weight: .light)).foregroundStyle(muted).padding(.top, 6)
            }.frame(maxWidth: width, alignment: .leading)
        }
    }
    private var photoPanel: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(ink.opacity(0.035))
                if let photo = model.photo {
                    CroppedPhoto(image: photo, crop: model.crop).accessibilityLabel("Your chosen photo")
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo").font(.system(size: 25, weight: .ultraLight))
                        Text("A space for something you love").font(.system(size: 12))
                    }.foregroundStyle(muted)
                }
            }.frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ink.opacity(0.08)))
            HStack(spacing: 18) {
                PhotosPicker(selection: $model.selectedPhoto, matching: .images) {
                    Text(model.photo == nil ? "Choose from Photos" : "Change from Photos")
                }.help("Choose an image from your Photos library")
                Button("Choose file…") { model.choosePhotoFile() }
                if model.photo != nil {
                    Button("Crop…") { model.beginCrop() }.help("Zoom and reposition your photo")
                    Button { model.removePhoto() } label: { Image(systemName: "xmark") }.help("Remove photo").accessibilityLabel("Remove photo")
                }
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(muted)
        }
    }
    func label(_ title: String) -> some View { Text(title).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(muted) }
    func greeting(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        return hour < 12 ? "A little room for a good morning." : hour < 18 ? "A little room for a clear afternoon." : "A little room to slow down."
    }
    func appButton(_ app: LaunchItem) -> some View {
        Button { model.open(app.url) } label: {
            VStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().interpolation(.high).frame(width: 40, height: 40)
                Text(app.name).font(.system(size: 11)).lineLimit(1)
            }.frame(maxWidth: .infinity).padding(.vertical, 12).contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(QuietButtonStyle()).help("Open \(app.name)")
    }
    func folder(_ name: String, symbol: String, url: URL) -> some View {
        Button { model.open(url) } label: { HStack(spacing: 12) { Image(systemName: symbol).frame(width: 16).foregroundStyle(muted); Text(name).font(.system(size: 13)); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(muted) } }.buttonStyle(.plain)
    }
}

struct CroppedPhoto: View {
    let image: NSImage
    let crop: PhotoCrop
    var body: some View {
        GeometryReader { geometry in
            let scale = max(geometry.size.width / max(1, image.size.width), geometry.size.height / max(1, image.size.height)) * crop.zoom
            let width = image.size.width * scale
            let height = image.size.height * scale
            Image(nsImage: image).resizable()
                .frame(width: width, height: height)
                .position(x: geometry.size.width / 2 + (width - geometry.size.width) / 2 * crop.x,
                          y: geometry.size.height / 2 + (height - geometry.size.height) / 2 * crop.y)
        }.clipped()
    }
}

struct PhotoCropEditor: View {
    @ObservedObject var model: DesktopModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Frame your photo").font(.system(size: 24, weight: .light))
            Text("Zoom in, then adjust the position to show your favorite part.").font(.system(size: 12)).foregroundStyle(.secondary)
            if let photo = model.photo {
                CroppedPhoto(image: photo, crop: model.draftCrop)
                    .frame(width: 468, height: 252)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Crop preview")
            }
            cropSlider("Zoom", value: $model.draftCrop.zoom, range: 1...4)
            cropSlider("Move left / right", value: $model.draftCrop.x, range: -1...1)
            cropSlider("Move up / down", value: $model.draftCrop.y, range: -1...1)
            Text("Your original photo stays unchanged.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Reset") { model.draftCrop = PhotoCrop() }
                Spacer()
                Button("Cancel") { model.editingCrop = false }.keyboardShortcut(.cancelAction)
                Button("Save") { model.saveCrop() }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 524)
    }
    func cropSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).frame(width: 130, alignment: .leading)
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
}

struct FavoritesEditor: View {
    @ObservedObject var model: DesktopModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Within Reach").font(.system(size: 24, weight: .light))
            Text("Choose your apps. Use the arrows to arrange them.").foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR SHORTCUTS").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    ScrollView {
                        VStack(spacing: 12) {
                            if model.draftFavorites.isEmpty { Text("Choose apps from the list.").foregroundStyle(.secondary).padding(.vertical, 20) }
                            ForEach(model.draftFavorites) { app in
                                HStack(spacing: 8) {
                                    appIcon(app)
                                    Text(app.name).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Button { model.moveFavorite(app.id, by: -1) } label: { Image(systemName: "chevron.up") }
                                        .disabled(model.draftIDs.first == app.id).accessibilityLabel("Move \(app.name) earlier")
                                    Button { model.moveFavorite(app.id, by: 1) } label: { Image(systemName: "chevron.down") }
                                        .disabled(model.draftIDs.last == app.id).accessibilityLabel("Move \(app.name) later")
                                    Button { model.toggleFavorite(app.id) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove \(app.name)")
                                }.buttonStyle(.borderless)
                            }
                        }.padding(.trailing, 8)
                    }
                }.frame(width: 310)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Search apps", text: $model.editorQuery).textFieldStyle(.roundedBorder)
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            if model.editorResults.isEmpty { Text("No matching apps").foregroundStyle(.secondary).padding(.vertical, 20) }
                            ForEach(model.editorResults) { app in
                                Button { model.toggleFavorite(app.id) } label: {
                                    HStack {
                                        appIcon(app)
                                        Text(app.name).lineLimit(1)
                                        Spacer()
                                        Image(systemName: model.draftIDs.contains(app.id) ? "checkmark.circle.fill" : "plus.circle")
                                            .foregroundStyle(model.draftIDs.contains(app.id) ? Color.accentColor : Color.secondary)
                                    }.padding(6).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("\(model.draftIDs.contains(app.id) ? "Deselect" : "Add") \(app.name)")
                            }
                        }
                    }
                }.frame(width: 260)
            }.frame(height: 320)
            Divider()
            HStack {
                Text("Saved on this Mac").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.editingFavorites = false }.keyboardShortcut(.cancelAction)
                Button("Save") { model.saveFavorites() }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 680)
    }
    func appIcon(_ app: LaunchItem) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 22, height: 22)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(Color.primary.opacity(configuration.isPressed ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 12))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Quiet Desktop", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Quiet Desktop", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Quiet Desktop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem(); item.submenu = appMenu; menu.addItem(item)
        let edit = NSMenu(); edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(); editItem.title = "Edit"; editItem.submenu = edit; menu.addItem(editItem)
        let view = NSMenu(); let fullscreen = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f"); fullscreen.keyEquivalentModifierMask = [.control, .command]; view.addItem(fullscreen)
        let viewItem = NSMenuItem(); viewItem.title = "View"; viewItem.submenu = view; menu.addItem(viewItem)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 860), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Quiet Desktop"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DesktopView())
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
