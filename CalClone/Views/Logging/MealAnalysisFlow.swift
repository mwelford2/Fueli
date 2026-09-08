import SwiftUI

/// Drives the multi-round meal analysis conversation: run the decomposition model,
/// surface each clarifying question one at a time, feed answers back, and once the
/// model is confident, resolve the breakdown into `NutritionFacts` via USDA.
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
    }

    enum Phase: Equatable {
        case idle
        case analyzing
        case asking(question: String)
        case resolving
        case done(NutritionFacts)
        case failed(message: String, stage: FailedStage)
    }

    private(set) var phase: Phase = .idle
    private(set) var clarifications: [AINutritionService.Clarification] = []
    /// The question currently on screen, awaiting an answer.
    private(set) var pendingQuestion: String?

    private var input: AINutritionService.AnalysisInput?
    /// The most recent decomposition — retained across a USDA failure so retrying
    /// the lookup doesn't re-run the model or lose any clarifying answers.
    private var lastDecomposition: NutritionAnalysisResult?
    /// Safety cap so a model that keeps asking can't loop forever.
    private let maxRounds = 6
    private var round = 0

    var isBusy: Bool {
        switch phase {
        case .analyzing, .resolving: return true
        default: return false
        }
    }

    func start(_ input: AINutritionService.AnalysisInput) {
        self.input = input
        self.clarifications = []
        self.round = 0
        self.lastDecomposition = nil
        runDecomposition()
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
        resolve(decomposition)
    }

    func retry() {
        switch phase {
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
        Task {
            do {
                let decomposition = try await AINutritionService.shared.decompose(input, clarifications: clarifications)
                self.lastDecomposition = decomposition

                let shouldAsk = decomposition.needsConfirmation
                    && (decomposition.clarifyingQuestion?.isEmpty == false)
                    && round < maxRounds
                    && !forceResolve

                if shouldAsk, let question = decomposition.clarifyingQuestion {
                    self.pendingQuestion = question
                    self.phase = .asking(question: question)
                } else {
                    self.resolve(decomposition)
                }
            } catch {
                self.phase = .failed(message: error.localizedDescription, stage: .decomposition)
            }
        }
    }

    private func resolve(_ decomposition: NutritionAnalysisResult) {
        phase = .resolving
        Task {
            do {
                let facts = try await AINutritionService.shared.resolveNutrition(
                    from: decomposition,
                    imageBase64: input?.imageBase64
                )
                self.phase = .done(facts)
            } catch {
                self.phase = .failed(message: error.localizedDescription, stage: .usdaLookup)
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
    @FocusState private var answerFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            switch coordinator.phase {
            case .idle:
                EmptyView()

            case .analyzing, .resolving:
                RotatingStatusView(messages: RotatingStatusView.mealAnalysis)

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

            case .done:
                RotatingStatusView(messages: ["Done!"])

            case .failed(let message, let stage):
                VStack(spacing: 8) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button(stage == .usdaLookup ? "Retry nutrition lookup" : "Try again") {
                        coordinator.retry()
                    }
                    .buttonStyle(.bordered)

                    if stage == .usdaLookup, !coordinator.clarifications.isEmpty {
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
    }

    private func submit() {
        let trimmed = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        answerText = ""
        coordinator.answer(trimmed)
    }
}
