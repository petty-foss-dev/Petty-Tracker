import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    private static let leadDayOptions = [1, 3, 7, 14, 30, 60, 90]

    @Environment(TrackerStore.self) private var store
    @Environment(\.reminders) private var reminders
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationStatus: UNAuthorizationStatus?
    @State private var exportFile: BackupFile?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var staged: StagedImport?
    @State private var busy = false
    @State private var notice: String?
    @State private var errorMessage: String?
    @AppStorage(Appearance.pureBlackKey) private var pureBlack = false

    var body: some View {
        TrackerForm {
            Section(overline: "Appearance") {
                Picker("Theme", selection: setting(\.themeMode)) {
                    ForEach(ThemeMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $pureBlack) {
                    VStack(alignment: .leading) {
                        Text("Pure black")
                        Text("True black backgrounds in dark mode, easier on OLED screens")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle(isOn: Binding(get: { store.settings.remindersEnabled }, set: setRemindersEnabled)) {
                    VStack(alignment: .leading) {
                        Text("Deadline reminders")
                        Text("Notify before dates arrive and on the day")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if store.settings.remindersEnabled && notificationStatus == .denied {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notifications are turned off for petty: Tracker.")
                            .foregroundStyle(Color.trackerPast)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                        }
                    }
                }
                leadPicker("Warranties", \.warrantyLeadDays)
                leadPicker("Subscription renewals", \.subscriptionLeadDays)
                leadPicker("Document expiry", \.documentLeadDays)
            } header: {
                Overline("Reminders")
            } footer: {
                Text("Reminders arrive around 9 AM.")
            }

            Section(overline: "Defaults") {
                NavigationLink {
                    CurrencyPicker(selection: setting(\.defaultCurrency))
                } label: {
                    LabeledContent("Currency", value: store.settings.defaultCurrency)
                }
            }

            Section {
                Button {
                    export()
                } label: {
                    Label("Export backup", systemImage: "square.and.arrow.up")
                }
                .fileExporter(
                    isPresented: $showExporter,
                    document: exportFile,
                    contentType: .zip,
                    defaultFilename: exportFile?.url.deletingPathExtension().lastPathComponent
                ) { result in
                    switch result {
                    case .success: notice = String(localized: "Backup saved")
                    case .failure(let error): errorMessage = error.localizedDescription
                    }
                }
                Button {
                    showImporter = true
                } label: {
                    Label("Import backup", systemImage: "square.and.arrow.down")
                }
                .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip]) { result in
                    switch result {
                    case .success(let url): stage(url)
                    case .failure(let error): errorMessage = error.localizedDescription
                    }
                }
                if busy {
                    HStack {
                        ProgressView()
                        Text("Working…").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Overline("Backup")
            } footer: {
                Text("Export saves every record, receipt, attachment and setting to a single ZIP file you choose. Import replaces everything on this iPhone with the contents of a backup. Backups without receipts work with petty: Tracker for Android too. Once you keep receipts, backups use a newer format that petty: Tracker for Android can't import.")
            }
            .disabled(busy)

            Section(overline: "About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                Text("Your records and files are stored only on this device. petty: Tracker has no internet access, accounts, analytics or ads.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Free and open source software under the GNU Affero General Public License v3.0 only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .trackerListStyle()
        .navigationTitle("Settings")
        .task(id: scenePhase) { notificationStatus = await reminders?.authorizationStatus() }
        .confirmationDialog("Replace all data?", isPresented: stagedBinding, titleVisibility: .visible, presenting: staged) { staged in
            Button("Replace", role: .destructive) { commit(staged) }
            Button("Cancel", role: .cancel) { BackupService(store: store).discard(staged) }
        } message: { staged in
            Text("Everything currently in petty: Tracker will be replaced by the backup (\(Formats.count(staged.recordCount, "record", "records")), \(Formats.count(staged.attachmentCount, "attachment", "attachments"))). Export first if you want to keep a copy.")
        }
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") {}
        }
        .errorAlert($errorMessage)
    }

    private var stagedBinding: Binding<Bool> {
        Binding(get: { staged != nil }, set: { if !$0 { staged = nil } })
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { value in update { $0[keyPath: keyPath] = value } }
        )
    }

    private func leadPicker(_ title: LocalizedStringKey, _ keyPath: WritableKeyPath<Settings, Int>) -> some View {
        let current = store.settings[keyPath: keyPath]
        let options = Set(Self.leadDayOptions + [current]).sorted()
        return Picker(title, selection: setting(keyPath)) {
            ForEach(options, id: \.self) { days in
                Text(days == 1 ? String(localized: "1 day before") : String(localized: "\(days) days before")).tag(days)
            }
        }
        .disabled(!store.settings.remindersEnabled)
    }

    private func update(_ transform: (inout Settings) -> Void) {
        do {
            try store.updateSettings(transform)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setRemindersEnabled(_ enabled: Bool) {
        update { $0.remindersEnabled = enabled }
        guard enabled else { return }
        Task {
            if await reminders?.authorizationStatus() == .notDetermined {
                _ = await reminders?.requestAuthorization()
            }
            notificationStatus = await reminders?.authorizationStatus()
            await reminders?.reschedule(store.data)
        }
    }

    private func export() {
        busy = true
        Task {
            defer { busy = false }
            do {
                exportFile = BackupFile(url: try await BackupService(store: store).export())
                showExporter = true
            } catch {
                errorMessage = String(localized: "The backup could not be completed. \(error.localizedDescription)")
            }
        }
    }

    private func stage(_ url: URL) {
        busy = true
        Task {
            defer { busy = false }
            do {
                staged = try await BackupService(store: store).stage(url)
            } catch let error as BackupError {
                errorMessage = String(localized: "That file is not a valid petty: Tracker backup (\(error.localizedDescription)). Nothing was changed.")
            } catch {
                errorMessage = String(localized: "The backup could not be read. Nothing was changed. \(error.localizedDescription)")
            }
        }
    }

    private func commit(_ staged: StagedImport) {
        do {
            try BackupService(store: store).commit(staged)
            reminders?.reset()
            notice = String(localized: "Restored \(Formats.count(staged.recordCount, "record", "records")) and \(Formats.count(staged.attachmentCount, "attachment", "attachments"))")
        } catch {
            errorMessage = String(localized: "The backup could not be restored. Nothing was changed. \(error.localizedDescription)")
        }
    }
}

struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    let url: URL

    init(url: URL) { self.url = url }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url)
    }
}
