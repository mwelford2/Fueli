import Foundation
import Testing
@testable import CalClone

@MainActor
struct HealthConnectionTests {
    @Test func mergeObservedSourcesByIdentity() {
        let active = HealthKitService.EnergySource(id: "example.provider", name: "Fitness App", hasActiveEnergy: true, hasRestingEnergy: false)
        let resting = HealthKitService.EnergySource(id: "example.provider", name: "Fitness App", hasActiveEnergy: false, hasRestingEnergy: true)
        let result = HealthKitService.mergeEnergySources(active: [active, active], resting: [resting])
        #expect(result.count == 1)
        #expect(result.first?.hasActiveEnergy == true)
        #expect(result.first?.hasRestingEnergy == true)
        #expect(result.first?.dataDescription == "Active + resting energy observed")
    }
    @Test func sameDisplayNameDoesNotMergeDifferentApps() {
        let a = HealthKitService.EnergySource(id: "a", name: "Fitness", hasActiveEnergy: true, hasRestingEnergy: false)
        let b = HealthKitService.EnergySource(id: "b", name: "Fitness", hasActiveEnergy: false, hasRestingEnergy: true)
        #expect(HealthKitService.mergeEnergySources(active: [a], resting: [b]).count == 2)
        #expect(a.dataDescription == "Active energy only observed")
        #expect(b.dataDescription == "Resting energy only observed")
    }
    @Test func emptySourcesAreNotConnections() {
        #expect(HealthKitService.mergeEnergySources(active: [], resting: []).isEmpty)
    }
    @Test func providersHaveOfficialHTTPSHelp() {
        #expect(FitnessHealthApp.allCases.count == 6)
        for app in FitnessHealthApp.allCases {
            #expect(!app.instructions.isEmpty)
            #expect(app.helpURL.scheme == "https")
            #expect(app.helpURL.host != nil)
        }
    }
}
