import SwiftUI

/// Drives the multi-round meal analysis conversation: run the decomposition model,
/// surface each clarifying question one at a time, feed answers back, and once the
/// user has reviewed it, resolve the breakdown through the selected database.
///
/// Shared by the "Describe Meal" and "Photo" flows.
@MainActor
@Observable
final class MealAnalysisCoordinator {
    /// Which step produced a failure, so `retry()` can resume from the right place
    /// instead of restarting the whole conversation.
    enum FailedStage: Equatable {
        case decomposition   // the AI decomposition call — retry re-runs it with the saved Q&A
        case usdaLookup      // the USDA resolve step — retry only re-hits USDA with the same breakdown
        case openFoodFactsLookup
    }

    enum Phase: Equatable {
        case idle
        case analyzing
        case asking(question: String)
        case reviewing
        case choosingMatch(Component, [USDAapiCaller.FDCFood])
        case choosingProducts(index: Int, query: String, page: FoodProductPage)
        case reviewingProduct(index: Int, product: FoodProductCandidate, reference: NutritionFacts)
        case resolving
        case done(NutritionFacts)
        case failed(message: String, stage: FailedStage)
    }

    private(set) var phase: Phase = .idle
    private(set) var database: MealFoodDatabase = .usda
    private(set) var enteredWithoutAI = false
    private(set) var clarifications: [AINutritionService.Clarification] = []
    /// The question currently on screen, awaiting an answer.
    private(set) var pendingQuestion: String?

    private var input: AINutritionService.AnalysisInput?
    /// The most recent decomposition — retained across a USDA failure so retrying
    /// the lookup doesn't re-run the model or lose any clarifying answers.
    var reviewedDecomposition: NutritionAnalysisResult?
    private var selectedMatches: [String: USDAapiCaller.FDCFood] = [:]
    private var lookupPlan: NutritionAnalysisResult?
    private var lastDecomposition: NutritionAnalysisResult?
    /// Safety cap so a model that keeps asking can't loop forever.
    private let maxRounds = 6
    private var round = 0
    private var operation: Task<Void, Never>?
    private var productReferences: [Int: NutritionFacts] = [:]
    private enum ProductWork {
        case search(Int, String, Int)
        case detail(Int, FoodProductCandidate)
    }
    private var lastProductWork: ProductWork?
    private let planner: @MainActor (NutritionAnalysisResult) async throws -> NutritionAnalysisResult
    private let resolver: @MainActor (NutritionAnalysisResult, [String: USDAapiCaller.FDCFood]) async throws -> NutritionFacts
    private let decomposer: @MainActor (AINutritionService.AnalysisInput, [AINutritionService.Clarification]) async throws -> NutritionAnalysisResult
    private let productSearch: @MainActor (String, Int) async throws -> FoodProductPage
    private let productDetail: @MainActor (String) async throws -> NutritionFacts

    init(
        planner: @escaping @MainActor (NutritionAnalysisResult) async throws -> NutritionAnalysisResult = {
            try await AINutritionService.shared.planNutritionLookup(from: $0)
        },
        resolver: @escaping @MainActor (NutritionAnalysisResult, [String: USDAapiCaller.FDCFood]) async throws -> NutritionFacts = {
            try await USDAapiCaller.shared.analyzeFood(result: $0, imageBase64: nil, selections: $1)
        },
        decomposer: @escaping @MainActor (AINutritionService.AnalysisInput, [AINutritionService.Clarification]) async throws -> NutritionAnalysisResult = {
            try await AINutritionService.shared.decompose($0, clarifications: $1)
        },
        productSearch: @escaping @MainActor (String, Int) async throws -> FoodProductPage = {
            try await OpenFoodFactsSearchService.shared.search(query: $0, page: $1)
        },
        productDetail: @escaping @MainActor (String) async throws -> NutritionFacts = {
            try await BarcodeLookupService.shared.lookupOpenFoodFactsOnly(barcode: $0)
        }
    ) {
        self.planner = planner
        self.resolver = resolver
        self.decomposer = decomposer
        self.productSearch = productSearch
        self.productDetail = productDetail
    }

    var isBusy: Bool {
        switch phase {
        case .analyzing, .resolving: return true
        default: return false
        }
    }

    func start(_ input: AINutritionService.AnalysisInput) {
        cancelPendingWork()
        self.input = input
        self.clarifications = []
        self.round = 0
        self.lastDecomposition = nil
        self.selectedMatches = [:]
        self.lookupPlan = nil
        self.productReferences = [:]
        self.lastProductWork = nil
        self.enteredWithoutAI = false
        self.reviewedDecomposition = nil
        self.pendingQuestion = nil
        runDecomposition()
    }

    func startWithoutAI(_ text: String) {
        cancelPendingWork()
        enteredWithoutAI = true
        do {
            let review = try ManualMealDescription.parse(text)
            input = nil; clarifications = []; selectedMatches = [:]; lookupPlan = nil
            productReferences = [:]; lastProductWork = nil; enteredWithoutAI = true
            pendingQuestion = nil; reviewedDecomposition = review; lastDecomposition = review
            phase = .reviewing
        } catch { phase = .failed(message: error.localizedDescription, stage: .decomposition) }
    }

    func selectDatabase(_ database: MealFoodDatabase) {
        guard self.database != database else { return }
        cancelPendingWork()
        self.database = database
        selectedMatches = [:]; lookupPlan = nil; productReferences = [:]; lastProductWork = nil
        phase = reviewedDecomposition == nil ? .idle : .reviewing
    }

    func cancelPendingWork() { operation?.cancel() }

    func resetReview() {
        cancelPendingWork()
        input = nil; reviewedDecomposition = nil; lastDecomposition = nil
        lookupPlan = nil; selectedMatches = [:]; productReferences = [:]; lastProductWork = nil
        clarifications = []; pendingQuestion = nil; enteredWithoutAI = false; phase = .idle
    }

    /// Submit the user's answer to the current question and continue.
    func answer(_ text: String) {
        guard let q = pendingQuestion else { return }
        clarifications.append(.init(question: q, answer: text))
        pendingQuestion = nil
        runDecomposition()
    }

    /// User chose to stop answering — resolve with what we have.
    func skipRemainingQuestions() {
        guard let decomposition = lastDecomposition else {
            // Nothing yet — force one more pass then resolve regardless.
            runDecomposition(forceResolve: true)
            return
        }
        reviewedDecomposition = decomposition
        phase = .reviewing
    }

    func retry() {
        switch phase {
        case .failed(_, .openFoodFactsLookup):
            switch lastProductWork {
            case .search(let index, let query, let page): searchProducts(at: index, query: query, page: page)
            case .detail(let index, let product): selectProduct(product, at: index)
            case nil: continueProductLookup()
            }
        case .failed(_, .usdaLookup):
            // Keep every clarifying answer and the model's breakdown — just hit USDA again.
            guard let decomposition = lastDecomposition else {
                runDecomposition()
                return
            }
            resolve(decomposition)
        default:
            // Decomposition failed (or nothing ran yet) — re-run it, still with the
            // clarifications gathered so far.
            runDecomposition()
        }
    }

    private func runDecomposition(forceResolve: Bool = false) {
        guard let input else { return }
        phase = .analyzing
        round += 1
        runOperation(stage: .decomposition) {
            let decomposition = try await self.decomposer(input, self.clarifications)
            try Task.checkCancellation()
            self.lastDecomposition = decomposition

            let shouldAsk = decomposition.needsConfirmation
                && (decomposition.clarifyingQuestion?.isEmpty == false)
                && self.round < self.maxRounds
                && !forceResolve

            if shouldAsk, let question = decomposition.clarifyingQuestion {
                self.pendingQuestion = question
                return .asking(question: question)
            } else {
                self.reviewedDecomposition = decomposition
                return .reviewing
            }
        }
    }

    func reviewedComponent(at index: Int) -> Component? {
        guard let review = reviewedDecomposition, review.components.indices.contains(index) else { return nil }
        return review.components[index]
    }

    func editComponent(at index: Int, _ edit: (inout Component) -> Void) {
        guard var review = reviewedDecomposition, review.components.indices.contains(index) else { return }
        edit(&review.components[index]); reviewedDecomposition = review
    }

    func removeComponent(at index: Int) {
        guard var review = reviewedDecomposition, review.components.indices.contains(index) else { return }
        review.components.remove(at: index); reviewedDecomposition = review
    }

    func addComponent() {
        reviewedDecomposition?.components.append(Component(label: "", fdcQuery: "", fallbackQueries: [],
            preferredDataTypes: ["Foundation", "SR Legacy", "Survey (FNDDS)"], brand: nil,
            quantity: Quantity(amount: 0, unit: "g"), estimatedGrams: 0, preparation: "", measureBasis: .as_packaged,
            negligible: false, confidence: 0))
    }

    var canContinueLookup: Bool {
        guard let review = reviewedDecomposition, !review.dishName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !review.components.isEmpty, review.components.count <= 50 else { return false }
        return review.components.allSatisfy { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.estimatedGrams.isFinite && $0.estimatedGrams > 0 && $0.estimatedGrams <= 100000 }
    }

    func continueLookup() {
        guard canContinueLookup, let corrected = reviewedDecomposition else { return }
        lastDecomposition = corrected
        lookupPlan = nil
        selectedMatches = [:]
        productReferences = [:]; lastProductWork = nil
        if database == .openFoodFacts { continueProductLookup() }
        else { resolve(corrected) }
    }

    func chooseFood(_ food: USDAapiCaller.FDCFood, for component: Component) {
        selectedMatches[USDAapiCaller.identity(for: component)] = food
        if let decomposition = lastDecomposition { resolve(decomposition) }
    }

    func returnToIngredientReview() { cancelPendingWork(); phase = .reviewing }

    private func continueProductLookup() {
        guard let review = lastDecomposition else { return }
        if let index = review.components.indices.first(where: { productReferences[$0] == nil }) {
            do { searchProducts(at: index, query: try IngredientSearchText.query(for: review.components[index])) }
            catch { phase = .failed(message: error.localizedDescription, stage: .openFoodFactsLookup) }
        } else {
            do { phase = .done(try MealRecordCalculation.assemble(review, references: productReferences)) }
            catch { phase = .failed(message: error.localizedDescription, stage: .openFoodFactsLookup) }
        }
    }

    func searchProducts(at index: Int, query: String, page: Int = 1) {
        guard lastDecomposition?.components.indices.contains(index) == true else { return }
        lastProductWork = .search(index, query, page)
        phase = .resolving
        runOperation(stage: .openFoodFactsLookup) {
            .choosingProducts(index: index, query: query, page: try await self.productSearch(query, page))
        }
    }

    func selectProduct(_ product: FoodProductCandidate, at index: Int) {
        guard lastDecomposition?.components.indices.contains(index) == true else { return }
        lastProductWork = .detail(index, product)
        phase = .resolving
        runOperation(stage: .openFoodFactsLookup) {
            let reference = try await self.productDetail(product.code)
            return .reviewingProduct(index: index, product: product, reference: reference)
        }
    }

    func confirmProduct() {
        guard case .reviewingProduct(let index, _, let reference) = phase,
              let component = lastDecomposition?.components[index] else { return }
        do {
            _ = try MealRecordCalculation.ingredient(component: component, reference: reference)
            productReferences[index] = reference
            continueProductLookup()
        } catch { phase = .failed(message: error.localizedDescription, stage: .openFoodFactsLookup) }
    }

    func returnToProductSearch() {
        guard case .reviewingProduct(let index, _, _) = phase, let review = lastDecomposition else { return }
        do { searchProducts(at: index, query: try IngredientSearchText.query(for: review.components[index])) }
        catch { phase = .failed(message: error.localizedDescription, stage: .openFoodFactsLookup) }
    }

    private func resolve(_ decomposition: NutritionAnalysisResult) {
        phase = .resolving
        runOperation(stage: .usdaLookup) {
            let plan: NutritionAnalysisResult
            if let lookupPlan = self.lookupPlan { plan = lookupPlan }
            else {
                // Manual structured ingredients already contain deterministic
                // queries; they do not need an AI query-planning call.
                plan = self.enteredWithoutAI ? ManualMealDescription.lookupPlan(from: decomposition) : try await self.planner(decomposition)
                try Task.checkCancellation()
                self.lookupPlan = plan
            }
            return .done(try await self.resolver(plan, self.selectedMatches))
        }
    }

    private func runOperation(stage: FailedStage, work: @escaping @MainActor () async throws -> Phase) {
        operation?.cancel()
        operation = Task {
            do {
                let next = try await work()
                try Task.checkCancellation()
                phase = next
            } catch AIServiceError.ambiguousFood(let component, let candidates) {
                guard !Task.isCancelled else { return }
                self.phase = .choosingMatch(component, candidates)
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(message: error.localizedDescription, stage: stage)
            }
        }
    }
}

/// The clarification card shown inline in a logging flow while the coordinator is
/// mid-conversation. Renders the spinner, the current question + answer field, or an
/// error with retry.
struct MealAnalysisProgressView: View {
    @Bindable var coordinator: MealAnalysisCoordinator
    @State private var answerText = ""
    @State private var productQuery = ""
    @FocusState private var answerFocused: Bool
    @FocusState private var editedWeight: Int?

    var body: some View {
        VStack(spacing: 14) {
            switch coordinator.phase {
            case .idle:
                EmptyView()

            case .analyzing:
                RotatingStatusView(messages: RotatingStatusView.mealAnalysis)

            case .resolving:
                ProgressView("Looking up ingredients in \(coordinator.database.title)…")
                Text("Your description and edits are preserved.").font(.caption).foregroundStyle(.secondary)

            case .asking(let question):
                VStack(alignment: .leading, spacing: 10) {
                    Label("Quick question", systemImage: "questionmark.circle.fill")
                        .font(.themeSubheadline.bold())
                        .foregroundStyle(Color.accentColor)
                    Text(question)
                        .font(.themeSubheadline)
                    TextField("Your answer", text: $answerText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($answerFocused)
                        .lineLimit(1...3)
                        .submitLabel(.send)
                        .onSubmit(submit)

                    HStack {
                        Button("Skip & estimate") {
                            answerText = ""
                            coordinator.skipRemainingQuestions()
                        }
                        .font(.caption)
                        Spacer()
                        Button("Send") { submit() }
                            .buttonStyle(.borderedProminent)
                            .disabled(answerText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !coordinator.clarifications.isEmpty {
                        Divider()
                        ForEach(coordinator.clarifications) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.question).font(.caption).foregroundStyle(.secondary)
                                Text(c.answer).font(.caption.bold())
                            }
                        }
                    }
                }
                .padding()
                .background(Color.themeCard)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .onAppear { answerFocused = true }

            case .choosingMatch(let component, let candidates):
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose USDA match: " + component.label).font(.headline)
                    Text("Compare identity and preparation before choosing. A broader record may omit toppings or preparation details; selecting it uses that record as an estimate. No alternative is selected automatically.").font(.caption)
                    ForEach(candidates, id: \.fdcId) { candidate in
                        Button(candidate.description + " · " + (candidate.dataType ?? "USDA") + " · \(candidate.fdcId)") {
                            coordinator.chooseFood(candidate, for: component)
                        }.buttonStyle(.bordered)
                    }
                    Button("No suitable match — edit ingredients") { coordinator.returnToIngredientReview() }
                }.padding()

            case .choosingProducts(let index, let query, let page):
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose product: " + (coordinator.reviewedComponent(at: index)?.label ?? "Ingredient")).font(.headline)
                    Text("Open Food Facts contains packaged products. Compare the actual brand, preparation and label. A search result is not an identified ingredient.").font(.caption)
                    TextField("Product or brand", text: $productQuery)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { coordinator.searchProducts(at: index, query: productQuery) }
                        .accessibilityLabel("Search Open Food Facts by product or brand")
                    Button("Search Open Food Facts") { coordinator.searchProducts(at: index, query: productQuery) }
                        .disabled(IngredientSearchText.clean(productQuery).isEmpty)
                    if page.products.isEmpty {
                        Text("No products were returned. Refine the product name, choose USDA, or edit the ingredients. No nutrition has been inferred.").font(.callout)
                    }
                    ForEach(page.products) { product in
                        Button { coordinator.selectProduct(product, at: index) } label: {
                            VStack(alignment: .leading) {
                                Text(product.name).multilineTextAlignment(.leading)
                                Text([product.brand, product.code].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.bordered)
                    }
                    HStack {
                        if page.page > 1 {
                            Button("Previous page") { coordinator.searchProducts(at: index, query: query, page: page.page - 1) }
                        }
                        if page.hasMore, page.page < 100 {
                            Button("Next page") { coordinator.searchProducts(at: index, query: query, page: page.page + 1) }
                        }
                    }
                    Button("Edit ingredients / change database") { coordinator.returnToIngredientReview() }
                    Link("Open Food Facts · ODbL", destination: URL(string: "https://world.openfoodfacts.org/data")!).font(.caption)
                }.padding().onAppear { productQuery = query }

            case .reviewingProduct(let index, let product, let reference):
                VStack(alignment: .leading, spacing: 12) {
                    Text("Confirm product match").font(.headline)
                    Text(reference.name)
                    Text("For ingredient: " + (coordinator.reviewedComponent(at: index)?.label ?? "")).font(.caption)
                    Text(reference.servingDescription).font(.caption)
                    Text("\(reference.caloriesValue.formatted()) kcal · Protein \(reference.proteinG.formatted()) g · Carbs \(reference.carbsG.formatted()) g · Fat \(reference.fatG.formatted()) g · Fiber \(reference.fiberG.formatted()) g").font(.caption)
                    Text("Community-supplied package nutrition. Confirm this is your product. Missing nutrients are never treated as zero.").font(.caption).foregroundStyle(.secondary)
                    if let component = coordinator.reviewedComponent(at: index) {
                        if let ingredient = try? MealRecordCalculation.ingredient(component: component, reference: reference),
                           let total = try? ingredient.nutrition() {
                            Text("At \(component.estimatedGrams.formatted()) g: \(total.calories.formatted()) kcal")
                            Button("Use this product for this ingredient") { coordinator.confirmProduct() }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Text(component.measureBasis != .as_packaged
                                 ? "Package nutrition must use an as-packaged weight. Edit the basis/weight, or use USDA for raw/cooked foods. No cooking conversion was assumed."
                                 : "This product has no usable gram-based reference. No volume-to-mass conversion was assumed. Choose another record or use USDA/manual entry.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Button("Choose another product") { coordinator.returnToProductSearch() }
                    Button("Edit ingredients / change database") { coordinator.returnToIngredientReview() }
                    Link("View Open Food Facts product", destination: URL(string: "https://world.openfoodfacts.org/product/" + product.code)!).font(.caption)
                }.padding()

            case .reviewing:
                if coordinator.reviewedDecomposition != nil {
                    VStack(alignment: .leading) {
                        Text(coordinator.enteredWithoutAI ? "Review entered ingredients" : "Review AI description").font(.headline)
                        Text("Edit the description and ingredients below, or choose a database and continue. Weights are estimates unless you measured them.").font(.caption)
                        Text("Meal description").font(.caption).foregroundStyle(.secondary)
                        TextField("Meal name", text: Binding(
                            get: { coordinator.reviewedDecomposition?.dishName ?? "" },
                            set: { coordinator.reviewedDecomposition?.dishName = $0 }))
                            .accessibilityLabel("Reviewed meal description")
                        ForEach(coordinator.reviewedDecomposition!.assumptions, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                        ForEach(Array(coordinator.reviewedDecomposition!.components.indices), id: \.self) { index in
                            TextField("Ingredient", text: Binding(
                                get: { coordinator.reviewedComponent(at: index)?.label ?? "" },
                                set: { value in coordinator.editComponent(at: index) { $0.label = value; $0.fdcQuery = value } }))
                            TextField("Preparation", text: Binding(
                                get: { coordinator.reviewedComponent(at: index)?.preparation ?? "" },
                                set: { value in coordinator.editComponent(at: index) { $0.preparation = value } }))
                            TextField("Brand (optional)", text: Binding(
                                get: { coordinator.reviewedComponent(at: index)?.brand ?? "" },
                                set: { value in coordinator.editComponent(at: index) { $0.brand = value.isEmpty ? nil : value } }))
                            Picker("Nutrition basis", selection: Binding(
                                get: { coordinator.reviewedComponent(at: index)?.measureBasis ?? .as_packaged },
                                set: { value in coordinator.editComponent(at: index) { $0.measureBasis = value } })) {
                                Text("Raw").tag(MeasureBasis.raw)
                                Text("Cooked").tag(MeasureBasis.cooked)
                                Text("As packaged").tag(MeasureBasis.as_packaged)
                            }
                            Text("Estimated weight (g)")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("Estimated weight (g)", value: Binding(
                                get: { coordinator.reviewedComponent(at: index)?.estimatedGrams ?? 0 },
                                set: { value in coordinator.editComponent(at: index) {
                                    $0.estimatedGrams = value; $0.quantity = Quantity(amount: value, unit: "g")
                                } }), format: .number).keyboardType(.decimalPad)
                                .focused($editedWeight, equals: index)
                                .accessibilityLabel("Estimated weight in grams for " + (coordinator.reviewedComponent(at: index)?.label ?? "ingredient")).accessibilityIdentifier("ingredient.grams.\(index)")
                            Button("Remove ingredient", role: .destructive) { coordinator.removeComponent(at: index) }
                            Divider()
                        }
                        Button("Add missing ingredient") { coordinator.addComponent() }
                        MealDatabasePicker(coordinator: coordinator)
                        Button("Continue to \(coordinator.database.title) Lookup") { coordinator.continueLookup() }
                            .buttonStyle(.borderedProminent).disabled(!coordinator.canContinueLookup)
                    }.padding()
                }

            case .done:
                RotatingStatusView(messages: ["Done!"])

            case .failed(let message, let stage):
                VStack(spacing: 8) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    if stage == .decomposition, coordinator.enteredWithoutAI {
                        Button("Edit ingredient text") { coordinator.resetReview() }
                    } else {
                        Button(stage != .decomposition ? "Retry nutrition lookup" : "Try again") {
                            coordinator.retry()
                        }
                        .buttonStyle(.bordered)
                    }

                    if stage != .decomposition {
                        Button("Edit ingredients / change database") { coordinator.returnToIngredientReview() }
                    }

                    if stage != .decomposition, !coordinator.clarifications.isEmpty {
                        Text("Your answers are saved — this only re-checks the nutrition database.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if editedWeight != nil || answerFocused {
                    Spacer()
                    Button("Done Editing") { editedWeight = nil; answerFocused = false }
                }
            }
        }
    }

    private func submit() {
        let trimmed = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        answerText = ""; answerFocused = false
        coordinator.answer(trimmed)
    }
}

struct MealDatabasePicker: View {
    @Bindable var coordinator: MealAnalysisCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Nutrition database", selection: Binding(get: { coordinator.database }, set: { coordinator.selectDatabase($0) })) {
                ForEach(MealFoodDatabase.allCases) { database in Text(database.title).tag(database) }
            }.pickerStyle(.menu).accessibilityLabel("Nutrition lookup database").accessibilityIdentifier("nutrition.database")
            Text(coordinator.database.explanation).font(.caption).foregroundStyle(.secondary)
            if coordinator.database == .openFoodFacts {
                Text("Use nutrition and weight on the same as-packaged basis. USDA is available for raw/cooked ingredients. Searches send ingredient text only, never your photo.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 8)
    }
}
