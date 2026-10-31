# Implementation notes

The current architecture, migration plan, executed verification, affected-file list and acceptance gaps are maintained in [OVERHAUL_STATUS.md](OVERHAUL_STATUS.md). Earlier incremental notes were consolidated because they incorrectly described subsequently completed work as missing.

Implementation followed dependency order: preserve existing stores; introduce validated serving calculations and independent save/log; improve exact barcode lookup; expose My Foods and deterministic recipes; separate photo description from USDA planning; add local receipt capture/OCR/review; add nutrition backup/restore; then test migrations, mocked networks, calculations and simulator workflows.

No destructive database recovery, cloud database, paid OCR, inventory system or direct vendor credential collection was introduced. Existing SavedMeal UUIDs remain the food-library identities; optional ingredient snapshots represent composed recipes. FoodLog retains historical nutrient values and library IDs independently.

Documentation references and assumptions are in the status report, [calorie evidence](CALORIE_EVIDENCE.md), [model capabilities](MODEL_CAPABILITIES.md) and [Health connections](HEALTH_CONNECTIONS.md). The requested full acceptance matrix is not yet fully verified; the status report lists the exact remaining gaps.
