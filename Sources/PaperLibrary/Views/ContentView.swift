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
    @State private var isSidebarVisible = true

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

    private var categoryFilter: Binding<String> {
        Binding(
            get: { selectedCategory },
            set: { category in
                selectedCategory = category
                selectedSubcategory = ""
                expandedCategory = category.isEmpty ? nil : category
            }
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
                welcomeView
            } else {
                libraryView
            }
        }
        .alert("Paper Library", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
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
        .onReceive(NotificationCenter.default.publisher(for: .togglePaperLibrarySidebar)) { _ in
            guard store.hasLibrary else { return }
            withAnimation {
                isSidebarVisible.toggle()
            }
        }
    }

    private var welcomeView: some View {
        ContentUnavailableView {
            Label("Paper Library", systemImage: "books.vertical.fill")
        } description: {
            Text("Choose your paper-library folder to browse and edit its catalog in a native Mac app.")
        } actions: {
            Button("Choose Library…") {
                store.chooseLibrary()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var libraryView: some View {
        VStack(spacing: 0) {
            OrganizerStatusHeader()
            Divider()
            catalogControls
            Divider()
            HSplitView {
                if isSidebarVisible {
                    sidebar
                        .frame(minWidth: 190, idealWidth: 230, maxWidth: 290, maxHeight: .infinity)
                }
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

    private var catalogControls: some View {
        VStack(spacing: 10) {
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
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(.separator.opacity(0.55), lineWidth: 1)
            }

            HStack(spacing: 8) {
                catalogMenu(title: "Field", selection: categoryFilter, options: store.categories.map(\.name))
                catalogMenu(title: "Venue", selection: $venueFilter, options: venues)
                catalogMenu(title: "Year", selection: $yearFilter, options: years)
                catalogMenu(title: "Track", selection: $trackFilter, options: tracks)
                catalogMenu(title: "Presentation", selection: $presentationFilter, options: presentations)

                Button {
                    clearFilters()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.separator.opacity(0.55), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help("Reset Search and Filters")

                Divider()
                    .frame(height: 32)

                sortControl
            }
        }
        .padding(12)
        .background(.bar)
    }

    private func catalogMenu(
        title: String,
        selection: Binding<String>,
        options: [String]
    ) -> some View {
        Menu {
            Button {
                selection.wrappedValue = ""
            } label: {
                if selection.wrappedValue.isEmpty {
                    Label("All \(title)s", systemImage: "checkmark")
                } else {
                    Text("All \(title)s")
                }
            }
            Divider()
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    if selection.wrappedValue == option {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selection.wrappedValue.isEmpty ? title : selection.wrappedValue)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 3)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.separator.opacity(0.55), lineWidth: 1)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help("Filter by \(title.lowercased())")
    }

    private var sortControl: some View {
        Menu {
            ForEach(CatalogSort.allCases) { option in
                Button {
                    sort = option
                } label: {
                    if sort == option {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption.weight(.bold))
                Text(sort.rawValue)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 3)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, 12)
            .frame(minWidth: 150, maxWidth: .infinity, minHeight: 40)
            .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(minWidth: 150, maxWidth: 1.3 * 150)
        .help("Sort Papers")
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
            }

            Section("Fields") {
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
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text(store.libraryName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Button("Change Library…") {
                    store.chooseLibrary()
                }
                .font(.caption)
                .buttonStyle(.link)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.bar)
        }
        .onChange(of: selectedCategory) { _, _ in
            selectedFile = filteredPapers.first?.file
        }
        .onChange(of: selectedSubcategory) { _, _ in
            selectedFile = filteredPapers.first?.file
        }
    }

    private var paperList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(filteredPapers.count) \(filteredPapers.count == 1 ? "paper" : "papers")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            if filteredPapers.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(filteredPapers, selection: listSelection) { paper in
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
