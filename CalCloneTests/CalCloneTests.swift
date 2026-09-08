//
//  CalCloneTests.swift
//  CalCloneTests
//
//  Created by Matteo Welford on 7/31/26.
//

import Testing
import UIKit
@testable import CalClone

struct CalCloneTests {

    @Test func example() async throws {
        let userText = "Medium banana"

        // These are the 5 FDC candidate descriptions you'd get back from a USDA FoodData Central search.
        // In production, CallUSDAapi.search(query:) returns these; here we hard-code samples to test the prompt.
        let candidates = [
            "Bananas, raw",
            "Banana, overripe, raw",
            "Banana chips",
            "Plantains, yellow, cooked",
            "Banana, dehydrated, or banana powder"
        ]

        let promptTemplate = """
        You are a food-matching classifier. You will be shown a food (as an image, a text description, or both) along with exactly 5 candidate food descriptions from a nutrition database, indexed 0 through 4.

        Your job: determine which of the 5 candidates best matches the food shown, and output ONLY that index number.

        MATCHING CRITERIA (in priority order):
        1. Core food identity — is it the same base food? (e.g. "chicken breast" vs "chicken thigh" vs "chicken nuggets" are different foods)
        2. Preparation method — grilled, fried, baked, raw, steamed, etc.
        3. Form/cut — whole, sliced, diced, shredded, ground
        4. Additional qualifiers — fat content (whole/skim/2%), skin on/off, bone in/out, seasoning, brand vs generic

        IF GIVEN AN IMAGE:
        - First silently identify: the food item(s), visible preparation style, portion/cut, and any visible sauces, coatings, or seasoning.
        - Ignore plate, garnish, or background items unless they are clearly part of the dish.
        - Use this identification to compare against the 5 candidates.

        IF GIVEN TEXT:
        - Match on the most specific overlapping terms, not just the first shared word (e.g. "fried rice with egg" should not match "white rice, cooked" over a candidate that says "rice, fried, with egg").

        TIE-BREAKING / AMBIGUITY:
        - If two candidates seem equally close, prefer the one that matches preparation method over the one that only matches the base ingredient.
        - You must always pick exactly one index, even if no candidate is a perfect match — choose the closest.

        OUTPUT FORMAT (strict):
        Respond with a single character: 0, 1, 2, 3, or 4.
        No words, no punctuation, no explanation, no newline before or after.

        ---
        User's food:
        {{USER_INPUT}}  (text description and/or image)

        Candidate descriptions:
        0: {{CANDIDATE_0}}
        1: {{CANDIDATE_1}}
        2: {{CANDIDATE_2}}
        3: {{CANDIDATE_3}}
        4: {{CANDIDATE_4}}
        """

        // Fill in the placeholders with the user's input and the FDC candidates.
        // {{USER_INPUT}} becomes the text description. When an image is also attached (see below),
        // the model will use both the text label and the visual to make its decision.
        let filledPrompt = promptTemplate
            .replacingOccurrences(of: "{{USER_INPUT}}", with: userText)
            .replacingOccurrences(of: "{{CANDIDATE_0}}", with: candidates[0])
            .replacingOccurrences(of: "{{CANDIDATE_1}}", with: candidates[1])
            .replacingOccurrences(of: "{{CANDIDATE_2}}", with: candidates[2])
            .replacingOccurrences(of: "{{CANDIDATE_3}}", with: candidates[3])
            .replacingOccurrences(of: "{{CANDIDATE_4}}", with: candidates[4])

        
        // Text-only: pass the filled prompt as the user message.
        // prompt: "" overrides the default fdc_ingredient_prompt system message so the model
        // only sees the classifier instructions (which are already in filledPrompt).
        let response = try await AINutritionService.shared.runRawText(userText: filledPrompt, imageBase64: nil, prompt: "")
        print("AI selected candidate index: \(response)")  // Expected: "0" (Bananas, raw)

        // ── To plug in the user's original photo ────────────────────────────────────────
        // 1. Get the UIImage captured by PhotoCaptureFlowView or BarcodeScanFlowView.
        //    let image: UIImage = <the photo from your flow>
        //
        // 2. Encode it the same way AINutritionService.analyzePhoto(_:) does:
        //    let base64 = image.jpegData(compressionQuality: 0.7)!.base64EncodedString()
        //
        // 3. Replace {{USER_INPUT}} with a short label — the model will use the image for details:
        //    let filled = promptTemplate
        //        .replacingOccurrences(of: "{{USER_INPUT}}", with: "see attached image")
        //        .replacingOccurrences(of: "{{CANDIDATE_0}}", with: candidates[0])
        //        ... (same for 1-4)
        //
        // 4. Call runRawText with both text and image:
        //    let response = try await serv.runRawText(userText: filled, imageBase64: base64, prompt: "")
        // ────────────────────────────────────────────────────────────────────────────────
    }

}
