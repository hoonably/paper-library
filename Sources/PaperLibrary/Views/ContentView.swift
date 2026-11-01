import SwiftUI

private enum CatalogSort: String, CaseIterable, Identifiable {
    case dateAdded = "Date Added"
    case title = "Title"
    case field = "Field"
    case year = "Year"
    case venue = "Venue"
    case presentation = "Presentation"

    var id: String { rawValue }
}

private enum SidebarSelection: Hashable {
    case allPapers
    case category(String)
    case subcategory(category: String, name: String)
}

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore

    @State private var selectedCategory = ""
    @State private var selectedSubcategory = ""
    @State private var expandedCategory: String?
    @State private var selectedFile: String?
    @State private var searchText = ""
    @State private var venueFilter = ""
    @State private var yearFilter = ""
    @State private var trackFilter = ""
    @State private var presentationFilter = ""
    @State private var sort: CatalogSort = .dateAdded
    @State private var editingPaper: Paper?

    private var venues: [String] {
        unique(store.papers.map(\.venue))
    }

    private var years: [String] {
        unique(store.papers.map(\.year)).sorted { (Int($0) ?? 0) > (Int($1) ?? 0) }
    }

    private var presentations: [String] {
        let order = ["Oral", "Spotlight", "Poster", "Preprint"]
        return unique(store.papers.map(\.presentation)).sorted {
            (order.firstIndex(of: $0) ?? order.count) < (order.firstIndex(of: $1) ?? order.count)
        }
    }

    private var tracks: [String] {
        unique(store.papers.map(\.track))
    }

    private var filteredPapers: [Paper] {
        let query = searchText.trimmed.foldedForSearch
        let filtered = store.papers.filter { paper in
            (selectedCategory.isEmpty || paper.category == selectedCategory) &&
            (selectedSubcategory.isEmpty || paper.subcategory == selectedSubcategory) &&
            (venueFilter.isEmpty || paper.venue == venueFilter) &&
            (yearFilter.isEmpty || paper.year == yearFilter) &&
            (trackFilter.isEmpty || paper.track == trackFilter) &&
            (presentationFilter.isEmpty || paper.presentation == presentationFilter) &&
            (query.isEmpty || paper.searchableText.contains(query))
        }
        return filtered.sorted { left, right in
            switch sort {
            case .dateAdded:
                return left.addedAt == right.addedAt
                    ? left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
                    : left.addedAt > right.addedAt
            case .title:
                return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            case .field:
                return left.category == right.category
                    ? left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
                    : left.category.localizedCaseInsensitiveCompare(right.category) == .orderedAscending
            case .year:
                return left.year == right.year
                    ? left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
                    : (Int(left.year) ?? 0) > (Int(right.year) ?? 0)
            case .venue:
                return left.venue == right.venue
                    ? left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
                    : left.venue.localizedCaseInsensitiveCompare(right.venue) == .orderedAscending
            case .presentation:
                let order = ["Oral", "Spotlight", "Poster", "Preprint"]
                let leftRank = order.firstIndex(of: left.presentation) ?? order.count
                let rightRank = order.firstIndex(of: right.presentation) ?? order.count
                return leftRank == rightRank
                    ? left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
                    : leftRank < rightRank
            }
        }
    }

    private var selectedPaper: Paper? {
        guard let effectiveSelectedFile else { return nil }
        return store.papers.first(where: { $0.file == effectiveSelectedFile })
    }

    private var effectiveSelectedFile: String? {
        if let selectedFile, filteredPapers.contains(where: { $0.file == selectedFile }) {
            return selectedFile
        }
        return filteredPapers.first?.file
    }

    private var listSelection: Binding<String?> {
        Binding(
            get: { effectiveSelectedFile },
            set: { selectedFile = $0 }
        )
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(
            get: {
                if selectedCategory.isEmpty {
                    return .allPapers
                }
                if selectedSubcategory.isEmpty {
                    return .category(selectedCategory)
                }
                return .subcategory(category: selectedCategory, name: selectedSubcategory)
            },
            set: { selection in
                guard let selection else { return }
                switch selection {
                case .allPapers:
                    selectedCategory = ""
                    selectedSubcategory = ""
                    expandedCategory = nil
                case let .category(category):
                    selectedCategory = category
                    selectedSubcategory = ""
                    expandedCategory = category
                case let .subcategory(category, subcategory):
                    selectedCategory = category
                    selectedSubcategory = subcategory
                    expandedCategory = category
                }
            }
        )
    }

    var body: some View {
        Group {
            if !store.hasLibrary {
                storageUnavailableView
            } else {
                libraryView
            }
        }
        .tint(LibraryStyle.accent)
        .alert("Paper Library", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .sheet(isPresented: $store.isShowingAutomationSetup) {
            AutomationSetupView()
                .environmentObject(store)
        }
        .overlay(alignment: .bottom) {
            if let notice = store.noticeMessage {
                Text(notice)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8, y: 3)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { store.noticeMessage = nil }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.noticeMessage)
        .onChange(of: store.noticeMessage) { _, message in
            guard message != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                store.noticeMessage = nil
            }
        }
        .task(id: store.libraryURL) {
            guard store.libraryURL != nil else { return }
            while !Task.isCancelled {
                store.refreshOrganizerStatus()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var storageUnavailableView: some View {
        VStack(alignment: .leading, spacing: 24) {
            if case let .destinationConflict(path) = store.storageAccessError as? StorageError {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 38)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 8) {
                    Text("PDF folder already exists").font(.title.bold())
                    Text("Move the existing item to another location in Finder, then return here and try again.")
                        .foregroundStyle(.secondary)
                }
                Label(path, systemImage: "folder")
                    .font(.callout).textSelection(.enabled)
                HStack {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    Button("Try Again") { store.allowLibraryAccess() }
                }
                .controlSize(.large)
            } else {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(LibraryStyle.accent)
                    .frame(width: 64, height: 64)
                    .background(LibraryStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your papers, in one place")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Paper Library saves PDFs in your Documents folder. Allow access when macOS asks so you can organize, open, and find your papers.")
                        .font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Label("PDFs · Documents / Paper Library / Papers", systemImage: "folder")
                    Label("Catalog and settings · stored on this Mac", systemImage: "internaldrive")
                    Label("Finder action · starts only when you add PDFs", systemImage: "cursorarrow.click")
                }
                .font(.callout)
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                if let error = store.storageAccessError {
                    Label {
                        Text(error.localizedDescription).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.callout).foregroundStyle(.secondary)
                    if isStoragePermissionError {
                        Text("Enable Documents Folder for Paper Library in System Settings → Privacy & Security → Files and Folders, then try again.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 12) {
                    Button(store.storageAccessError == nil ? "Continue" : "Try Again") {
                        store.allowLibraryAccess()
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    if isStoragePermissionError {
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                        }
                        .controlSize(.large)
                    }
                }
                Text("Only Documents access is needed. You can close this window and finish setup later.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(36).frame(maxWidth: 580, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var isStoragePermissionError: Bool {
        guard let error = store.storageAccessError as NSError? else { return false }
        if error.domain == NSCocoaErrorDomain {
            return [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(error.code)
        }
        return error.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(error.code)
    }

    private var libraryView: some View {
        VStack(spacing: 0) {
            OrganizerStatusHeader { searchField }
            Divider()
            catalogControls
            Divider()
            HSplitView {
                sidebar
                    .frame(minWidth: 190, idealWidth: 230, maxWidth: 290, maxHeight: .infinity)
                paperList
                    .frame(minWidth: 340, idealWidth: 430, maxWidth: 560, maxHeight: .infinity)
                Group {
                    if let selectedPaper {
                        if let editingPaper, editingPaper.file == selectedPaper.file {
                            PaperEditorView(
                                paper: editingPaper,
                                onSave: { edited in
                                    let saved = store.save(edited)
                                    if saved {
                                        self.editingPaper = nil
                                        selectedFile = edited.file
                                    }
                                    return saved
                                },
                                onCancel: {
                                    self.editingPaper = nil
                                },
                                onDelete: {
                                    let deleted = store.delete(selectedPaper)
                                    if deleted {
                                        self.editingPaper = nil
                                        selectedFile = nil
                                    }
                                    return deleted
                                }
                            )
                        } else {
                            PaperDetailView(paper: selectedPaper) {
                                editingPaper = selectedPaper
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "Select a Paper",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("Choose a paper from the catalog to see its summary and metadata.")
                        )
                    }
                }
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: effectiveSelectedFile) { _, file in
            if editingPaper?.file != file {
                editingPaper = nil
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search titles, authors, and key ideas", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }

    private var catalogControls: some View {
        HStack(spacing: 10) {
            catalogMenu(title: "Venue", systemImage: "building.columns", selection: $venueFilter, options: venues)
            catalogMenu(title: "Year", systemImage: "calendar", selection: $yearFilter, options: years)
            Menu {
                filterPicker("Track", selection: $trackFilter, options: tracks).pickerStyle(.menu)
                filterPicker("Presentation", selection: $presentationFilter, options: presentations).pickerStyle(.menu)
            } label: {
                Label("More filters", systemImage: "line.3.horizontal.decrease")
            }
            .fixedSize()
            if !trackFilter.isEmpty || !presentationFilter.isEmpty {
                Text([trackFilter, presentationFilter].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if hasActiveFilters {
                Button("Reset") { clearFilters() }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reset search and filters")
            }
            Spacer(minLength: 0)
            sortControl
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func filterPicker(_ title: String, selection: Binding<String>, options: [String]) -> some View {
        Picker(title, selection: selection) {
            Text("All").tag("")
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
    }

    private func catalogMenu(title: String, systemImage: String, selection: Binding<String>, options: [String]) -> some View {
        Menu {
            filterPicker(title, selection: selection, options: options)
                .pickerStyle(.inline)
        } label: {
            Label(selection.wrappedValue.isEmpty ? title : selection.wrappedValue, systemImage: systemImage)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityLabel("Filter by \(title.lowercased())")
        .accessibilityValue(selection.wrappedValue.isEmpty ? "All" : selection.wrappedValue)
    }

    private var sortControl: some View {
        Menu {
            Picker("Sort by", selection: $sort) {
                ForEach(CatalogSort.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
        }
        .help("Sort papers")
        .fixedSize()
    }

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            Section("Library") {
                Label {
                    HStack {
                        Text("All Papers")
                        Spacer()
                        Text("\(store.papers.count)").foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "books.vertical")
                }
                .tag(SidebarSelection.allPapers)

                ForEach(store.categories, id: \.name) { category in
                    let subcategories = store.subcategories(in: category.name)

                    HStack(spacing: 7) {
                        Image(systemName: expandedCategory == category.name ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 9)
                            .opacity(subcategories.isEmpty ? 0 : 1)
                        Image(systemName: expandedCategory == category.name && !subcategories.isEmpty ? "folder.fill" : "folder")
                        Text(category.name)
                        Spacer()
                        Text("\(category.count)")
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarSelection.category(category.name))

                    if expandedCategory == category.name {
                        ForEach(subcategories, id: \.name) { subcategory in
                            HStack(spacing: 7) {
                                Image(systemName: "folder")
                                Text(subcategory.name)
                                Spacer()
                                Text("\(subcategory.count)")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 24)
                            .tag(SidebarSelection.subcategory(
                                category: category.name,
                                name: subcategory.name
                            ))
                        }
                    }
                }
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            selectedFile = filteredPapers.first?.file
        }
        .onChange(of: selectedSubcategory) { _, _ in
            selectedFile = filteredPapers.first?.file
        }
    }

    private var paperList: some View {
        let processingPapers = store.organizerStatus.processingPapers

        return VStack(spacing: 0) {
            HStack {
                Text("\(filteredPapers.count) \(filteredPapers.count == 1 ? "paper" : "papers")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !processingPapers.isEmpty {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("\(processingPapers.count) processing")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                }
                Spacer()
                if hasActiveFilters {
                    Button("Clear Filters") { clearFilters() }
                        .font(.caption)
                        .buttonStyle(.link)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)

            if filteredPapers.isEmpty && processingPapers.isEmpty {
                if store.papers.isEmpty, !hasActiveFilters {
                    ContentUnavailableView {
                        Label("Add your first paper", systemImage: "doc.badge.plus")
                    } description: {
                        Text("In Finder, right-click a PDF and choose Services → Move to Paper Library. The PDF moves into your waiting queue.")
                    } actions: {
                        if !store.isAutomationConfigured {
                            Button("Set Up Automation") { store.presentAutomationSetup() }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Open Finder") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser) }
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label("No matching papers", systemImage: "magnifyingglass")
                    } description: {
                        Text("Try a different search or clear the filters to see your library.")
                    } actions: {
                        Button("Clear Search and Filters") { clearFilters() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                List(selection: listSelection) {
                    if !processingPapers.isEmpty {
                        Section("Processing") {
                            ForEach(processingPapers) { processingPaper in
                                ProcessingPaperRowView(paper: processingPaper)
                            }
                        }
                    }

                    ForEach(filteredPapers) { paper in
                        PaperRowView(paper: paper)
                            .tag(paper.file)
                            .contextMenu {
                                Button("Open PDF") { store.openPDF(paper) }
                                Button("Show in Finder") { store.revealPDF(paper) }
                                Divider()
                                Button("Edit Metadata…") {
                                    selectedFile = paper.file
                                    editingPaper = paper
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var hasActiveFilters: Bool {
        !searchText.isEmpty || !selectedCategory.isEmpty || !selectedSubcategory.isEmpty || !venueFilter.isEmpty ||
            !yearFilter.isEmpty || !trackFilter.isEmpty || !presentationFilter.isEmpty
    }

    private func clearFilters() {
        searchText = ""
        selectedCategory = ""
        selectedSubcategory = ""
        expandedCategory = nil
        venueFilter = ""
        yearFilter = ""
        trackFilter = ""
        presentationFilter = ""
    }

    private func unique(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

enum LibraryStyle {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0.47, green: 0.75, blue: 0.62, alpha: 1)
        }
        return NSColor(red: 0.145, green: 0.42, blue: 0.33, alpha: 1)
    })
}
