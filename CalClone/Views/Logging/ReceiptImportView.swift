import SwiftUI
import SwiftData
import Vision
import VisionKit
import PhotosUI

struct ReceiptLine: Identifiable, Equatable {
    var id = UUID()
    var original: String
    var name: String
    var confidence: Float
    var skip: Bool
    var imported = false
    var purchaseQuantity: Double? = nil
    var purchaseUnit: String? = nil
}
enum ReceiptParser {
    static func parse(_ text: String, confidence: Float) -> ReceiptLine {
        let upper = text.uppercased()
        let metadata = ["SUBTOTAL", "SUB TOTAL", "TOTAL", "TAX", "VISA", "CASH", "CHANGE", "COUPON", "DISCOUNT", "SAVINGS", "BALANCE", "MASTERCARD"]
        var name = upper.replacingOccurrences(of: #"\s+\$?-?\d+[.,]\d{2}\s*[A-Z]?$"#, with: "", options: .regularExpression)
        for (short, full) in [("CHK", "CHICKEN"), ("BRST", "BREAST"), ("BNLS", "BONELESS"), ("ORG", "ORGANIC"), ("YGRT", "YOGURT")] {
            name = name.replacingOccurrences(of: "\\b" + short + "\\b", with: full, options: .regularExpression)
        }
        // Purchase weights are metadata; never become a food's nutrition serving.
        name = name.replacingOccurrences(of: #"\b\d+(?:\.\d+)?\s*(?:LB|OZ|KG|G|EA)\b"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var row = ReceiptLine(original: text, name: name.lowercased(), confidence: confidence,
                           skip: metadata.contains { upper.hasPrefix($0) } || name.isEmpty)
        let pattern = try? NSRegularExpression(pattern: #"\b(\d+(?:\.\d+)?)\s*(LB|OZ|KG|G|EA)\b"#)
        let range = NSRange(upper.startIndex..., in: upper)
        if let match = pattern?.firstMatch(in: upper, range: range),
           let quantity = Range(match.range(at: 1), in: upper), let unit = Range(match.range(at: 2), in: upper) {
            row.purchaseQuantity = Double(upper[quantity]); row.purchaseUnit = String(upper[unit]).lowercased()
        }
        return row
    }
    struct Fragment {
        var text: String
        var x: Double
        var y: Double
        var height: Double
        var confidence: Float
    }
    static func reconstruct(_ fragments: [Fragment]) -> [ReceiptLine] {
        var groups: [[Fragment]] = []
        for fragment in fragments.sorted(by: { $0.y > $1.y }) {
            if let index = groups.firstIndex(where: { group in
                guard let first = group.first else { return false }
                return abs(first.y - fragment.y) < max(first.height, fragment.height) * 0.5
            }) { groups[index].append(fragment) }
            else { groups.append([fragment]) }
        }
        return groups.map { group in
            let text = group.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")
            return parse(text, confidence: group.map(\.confidence).min() ?? 0)
        }
    }
    static func recognize(_ image: UIImage, preferStructured: Bool = true) async throws -> [ReceiptLine] {
        guard let cgImage = image.cgImage else { throw CocoaError(.fileReadCorruptFile) }
        return try await Task.detached {
            if #available(iOS 26.0, *), preferStructured {
                do {
                    var request = RecognizeDocumentsRequest()
                    request.textRecognitionOptions.useLanguageCorrection = true
                    request.barcodeDetectionOptions.enabled = false
                    let documents = try await request.perform(on: cgImage)
                    let fragments = documents.flatMap { $0.document.text.lines }.compactMap { line -> Fragment? in
                        guard let text = line.topCandidates(1).first else { return nil }
                        let left = min(line.topLeft.x, line.bottomLeft.x)
                        let bottom = min(line.bottomLeft.y, line.bottomRight.y)
                        let top = max(line.topLeft.y, line.topRight.y)
                        return Fragment(text: text.string, x: left, y: (bottom + top) / 2,
                            height: top - bottom, confidence: text.confidence)
                    }
                    if !fragments.isEmpty { return reconstruct(fragments) }
                } catch is CancellationError { throw CancellationError() }
                catch { /* Unsupported/unclear document: use accurate text OCR below. */ }
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // UIImage drawing normalizes orientation before this method is called.
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            let fragments = (request.results ?? []).compactMap { observation -> Fragment? in
                guard let text = observation.topCandidates(1).first else { return nil }
                return Fragment(text: text.string, x: observation.boundingBox.minX, y: observation.boundingBox.midY,
                    height: observation.boundingBox.height, confidence: text.confidence)
            }
            return reconstruct(fragments)
        }.value
    }
}

struct ReceiptCamera: UIViewControllerRepresentable {
    var completed: ([UIImage]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completed) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController(); controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completed: ([UIImage]) -> Void
        init(_ completed: @escaping ([UIImage]) -> Void) { self.completed = completed }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            completed((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { completed([]) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Swift.Error) { completed([]) }
    }
}

struct ReceiptImportView: View {
    let onFinished: () -> Void
    @Environment(\.modelContext) private var context
    @Query private var foods: [SavedMeal]
    @State private var camera = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var pages: [UIImage] = []
    @State private var rows: [ReceiptLine] = []
    @State private var busy = false
    @State private var error: String?
    @State private var selectedRow: UUID?
    @State private var existingRow: UUID?
    @State private var existingSearch = ""
    @State private var matches: [USDAapiCaller.FDCFood] = []
    var body: some View {
        NavigationStack {
            List {
                Section("On-device receipt OCR") {
                    Text("Receipts stay on this device. Review each row; purchase quantity is never treated as food consumed.").font(.caption)
                    Button("Scan Receipt Pages") { camera = true }.disabled(!VNDocumentCameraViewController.isSupported || busy)
                    PhotosPicker("Choose Receipt Photos", selection: $photos, maxSelectionCount: 20, matching: .images).disabled(busy)
                    if busy { ProgressView("Reading receipt…") }
                    if let error { Text(error).foregroundStyle(.red) }
                    Text("\(rows.count) rows · \(rows.filter(\.imported).count) imported · \(rows.filter(\.skip).count) skipped · \(rows.filter { !$0.skip && !$0.imported }.count) unresolved")
                }
                if !pages.isEmpty {
                    Section("Original pages") {
                        DisclosureGroup("Show receipt images") {
                            ForEach(pages.indices, id: \.self) { index in Image(uiImage: pages[index]).resizable().scaledToFit() }
                        }
                    }
                }
                ForEach($rows) { $row in
                    Section {
                        Text(row.original).font(.caption).foregroundStyle(.secondary)
                        if row.confidence < 0.8 { Label("Low OCR confidence — review", systemImage: "exclamationmark.triangle") }
                        TextField("Product name", text: $row.name)
                        HStack {
                            TextField("Purchase quantity (optional)", value: $row.purchaseQuantity, format: .number).keyboardType(.decimalPad)
                            TextField("Unit", text: Binding(get: { row.purchaseUnit ?? "" }, set: { row.purchaseUnit = $0 }))
                        }
                        Text("Purchase quantity is metadata, not the saved food serving.").font(.caption)
                        Toggle("Skip / non-food", isOn: $row.skip)
                        if row.imported { Label("Saved to My Foods", systemImage: "checkmark.circle") }
                        else if !row.skip {
                            Button("Choose existing saved food") { existingSearch = row.name; existingRow = row.id }
                                .disabled(foods.isEmpty || busy)
                            Button("Search USDA — review match") { search(row) }.disabled(busy || row.name.isEmpty)
                        }
                    }
                }
            }.themedScreenBackground().navigationTitle("Scan Receipt")
                .toolbar { Button("Done", action: onFinished) }
                .sheet(isPresented: $camera) { ReceiptCamera { images in camera = false; if !images.isEmpty { process(images) } } }
                .sheet(isPresented: Binding(get: { selectedRow != nil }, set: { if !$0 { selectedRow = nil } })) {
                    NavigationStack {
                        List(matches, id: \.fdcId) { match in
                            Button(match.description + " · USDA \(match.fdcId)") { importMatch(match) }
                        }.navigationTitle("Choose exact food")
                            .toolbar { Button("No suitable match") { selectedRow = nil } }
                            .overlay { if matches.isEmpty { Text("No candidates. Correct the name and retry.") } }
                    }
                }
                .sheet(isPresented: Binding(get: { existingRow != nil }, set: { if !$0 { existingRow = nil } })) {
                    NavigationStack {
                        List(foods.filter { existingSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(existingSearch) }) { food in
                            Button(food.name + " · " + food.servingDescription) {
                                if let index = rows.firstIndex(where: { $0.id == existingRow }) {
                                    rows[index].name = food.name
                                    rows[index].imported = true
                                }
                                existingRow = nil
                            }
                        }.searchable(text: $existingSearch).navigationTitle("Choose saved food")
                            .toolbar { Button("Cancel") { existingRow = nil } }
                    }
                }
                .onChange(of: photos) { _, items in
                    Task {
                        var images: [UIImage] = []
                        for item in items { if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { images.append(image) } }
                        process(images)
                    }
                }
        }
    }
    private func process(_ images: [UIImage]) {
        busy = true; error = nil
        Task {
            do {
                for image in images {
                    let normalized = UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
                    let recognized = try await ReceiptParser.recognize(normalized)
                    pages.append(normalized); rows.append(contentsOf: recognized)
                }
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    private func search(_ row: ReceiptLine) {
        busy = true; error = nil
        Task {
            do { matches = try await USDAapiCaller.shared.search(query: row.name, dataTypes: ["Foundation", "SR Legacy", "Branded"]).foods; selectedRow = row.id }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    private func importMatch(_ match: USDAapiCaller.FDCFood) {
        guard !busy else { return }
        busy = true
        Task {
        defer { busy = false }
        do {
            let nutrients = try await USDAapiCaller.shared.foodDetail(id: match.fdcId).coreValues()
            func required(_ id: Int) throws -> Double {
                guard let value = nutrients[id], value.isFinite, value >= 0 else { throw NutritionValidationError.incomplete }
                return value
            }
            let calories = try required(1008), protein = try required(1003), carbs = try required(1005), fat = try required(1004), fiber = try required(1079)
            let name = match.description
            if !(try context.fetch(FetchDescriptor<SavedMeal>())).contains(where: { $0.nutritionSourceID == "USDA:\(match.fdcId)" }) {
                let food = SavedMeal(name: name, calories: Int(calories.rounded()), proteinG: protein,
                    carbsG: carbs, fatG: fat, fiberG: fiber, servingDescription: "100 g")
                food.caloriesExact = calories
                food.nutritionSourceID = "USDA:\(match.fdcId)"
                food.gramsPerServing = 100
                context.insert(food)
                try context.save()
            }
            if let index = rows.firstIndex(where: { $0.id == selectedRow }) { rows[index].imported = true }
            selectedRow = nil
        } catch { context.rollback(); self.error = error.localizedDescription; selectedRow = nil }
        }
    }
}
