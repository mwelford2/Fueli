# Calorie planning: evidence and implementation

Research checked 2026-10-31. These are starting rules informed by evidence, not a clinically validated personalized treatment algorithm.

## Manually entered maintenance burn

Setup → Your total daily burn and Settings → Goals & Profile both provide the same manual entry and live goal-intake preview. The number is total expenditure for a representative complete day, including resting energy and all activity. It is not the number of calories to eat, and workout calories alone are insufficient.

The baseline priority is manually entered total burn, then a saved Apple Health average, then the existing body/activity calculation. Neither resting energy nor steps/workouts are added to a manual baseline. A successful explicit Health import switches back to Health; an unsuccessful import preserves the manual baseline. Switching to activity estimates clears both saved baseline choices. Applying a manual burn skips activity questions in setup. The user can edit it later as activity/weight change.

A manual food-intake override remains a separate, higher-priority setting. The UI warns when it is active; turn it off to apply the goal-based intake. Draft values preview the goal adjustment and resulting intake before application. Numeric validation requires a finite 500–15,000 kcal/day value; these broad input bounds catch mistakes and are not clinically validated expenditure limits. Values retain Double precision and round for display/target presentation.

## Maintenance from Apple Health

Setup offers read-only permission for Active Energy and Resting Energy. These correspond to Apple's `activeEnergyBurned` and `basalEnergyBurned` quantities. A HealthKit statistics collection query merges sources and sums each type by local calendar day. Fueli adds the two values once; BMR, steps, and workouts are not added to the result.

The window is the previous 14 completed days, excluding today. An eligible day has finite nonnegative active kcal, positive resting kcal, with a readable value for both types. Raw sample-duration coverage is no longer an eligibility gate because providers may export valid daily aggregates. At least seven eligible days are required. These window and pairing rules are conservative engineering choices, not thresholds validated by a clinical study. Coverage cannot prove correct wear time or accurate calorie measurement. Missing/denied data is never filled with zero. A genuinely recorded zero active value is accepted.

A successful average is stored as optional profile fields with eligible-day count and window dates. Setup skips the step/workout questions. Manual calorie overrides still take precedence. The dashboard uses the saved full-day maintenance average, not today's incomplete active energy. Without an average, it uses the existing body/activity estimate. A snapshot remains until the user refreshes or disables it in Goals & Profile; it does not silently change with each Watch sync. Health-recorded active + resting energy is an estimate of total expenditure, not laboratory measurement of every physiological process.

Apple references: [resting energy](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/basalenergyburned), [active energy](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/activeenergyburned), [statistics collections](https://developer.apple.com/documentation/healthkit/hkstatisticscollectionquery). Retrieved through Context7. Read authorization completion does not prove data was granted.

## Adult goal adjustments

| Choice | Implemented starting adjustment |
| --- | --- |
| Cut | Requested weekly rate converted to a starting kcal dose, capped at the smallest of 25% maintenance, 750 kcal/day, and the energy equivalent of 0.7% body mass/week |
| Bulk | Requested dose capped at 10% maintenance |
| Recomp: fat loss | −10% maintenance, capped at 500 kcal/day |
| Recomp: maintenance | No adjustment |
| Recomp: lean gain | +5% maintenance |

The 7700 kcal/kg conversion only maps the existing rate slider to a starting dose. It does not predict weight change. Goal type determines direction, even if a legacy rate has the wrong sign. Automated targets have planning floors of 1500 kcal/day for men and 1200 for women; those are not universal safe minimums or individualized prescriptions. Manual targets are retained. No automatic deficit or surplus is assigned below age 18. Adults with pregnancy/breastfeeding, medical conditions, eating-disorder history, or special nutrition needs should use clinician-guided settings. The app does not assess these conditions.

## Clinical and intervention evidence

- [Jensen et al., 2013 AHA/ACC/TOS guideline](https://pmc.ncbi.nlm.nih.gov/articles/PMC5819889/): clinical recommendations for adults with overweight/obesity include 500–750 kcal/day deficits and individualized calorie restriction. This is not direct support for applying a fixed deficit to lean athletes or every adult. Fueli permits smaller doses and caps restriction; 25% is an app policy informed by moderate restriction, not a universal clinical cutoff.
- [Garthe et al., 2011](https://pubmed.ncbi.nlm.nih.gov/21558571/): compared slower versus faster weight-loss interventions in elite athletes. Findings support gradual loss when lean-mass/performance retention matters. Fueli uses 0.7% body mass/week as an upper starting-dose constraint, not a promise that a specific deficit produces that loss.
- [Helms et al., 2023](https://doi.org/10.1186/s40798-023-00651-y): small eight-week study in resistance-trained adults comparing maintenance and intended 5%/15% surpluses; faster gain was more clearly associated with skinfold increases than improved hypertrophy. This supports starting conservatively, but does not establish an optimal surplus for everyone. Fueli's 10% bulk cap and 5% lean-gain setting are policy choices within a conservative range, not clinical consensus.
- [Hall et al., 2011](https://pubmed.ncbi.nlm.nih.gov/21872751/): dynamic changes in expenditure/body composition undermine fixed linear calorie-to-weight predictions. Fueli labels the rate as requested rather than guaranteed and advises reviewing observed weight trends after 2–4 weeks. That review interval is a practical policy; no automatic titration is implemented.
- [Shcherbina et al., 2017](https://pubmed.ncbi.nlm.nih.gov/28538708/): validation of wrist devices found substantial energy-expenditure error. It motivates communicating uncertainty; it does not validate current Apple Watch models or this app's averaging algorithm.

- [Murphy and Koehler, 2022](https://pubmed.ncbi.nlm.nih.gov/34623696/): meta-analysis/meta-regression of resistance training with energy deficits found impaired lean-mass gains; around 500 kcal/day of deficit was associated with no lean-mass gain on average. This is not an individual biological threshold. It supports avoiding aggressive restriction when recomposition is the aim. Fueli caps the modest recomp fat-loss adjustment at 500 kcal/day.
- [Longland et al., 2016](https://pubmed.ncbi.nlm.nih.gov/26817506/): a four-week randomized trial in young men, under a large energy deficit and intensive training, found better lean/fat mass outcomes with higher protein. The short, highly supervised intervention does not establish an ideal recomp calorie dose, and Fueli does not reproduce its approximately 40% restriction. It illustrates why calorie percentages alone cannot promise recomposition.

For maintenance-focused recomp, no planned energy adjustment is applied: intake begins at the entered or imported expenditure estimate. Hall's dynamic energy-balance work supports revisiting the estimate as body weight/activity change rather than claiming a permanently exact maintenance intake. The same estimate can be wrong whether it came from manual entry or a wearable.

No direct trial establishes Fueli's exact recomp percentages; these are modest directional starting adjustments chosen by the user's focus. Resistance training and adequate nutrition remain necessary. Citations are available in setup and profile settings.

## Persistence and verification scope

Manual and Health baseline fields remain optional. Version 4 adds manualMaintenanceCalories and retains a frozen version 3 schema for lightweight migration. A versioned migration plan now covers the original and known interim schemas, with populated migration and corruption-preservation fixtures. The non-destructive error path remains. Preserve the original installation/store if an upgrade fails.

Tests cover active+resting averaging, missing/partial days, zero active energy, invalid quantities, excluding today, overlapping source coverage, replacing other estimates, manual overrides, goal caps/direction, minor-age behavior, and a disk-backed profile snapshot round trip. Physical-device permission and real Health history checks remain necessary.

Verification for the manual-burn follow-up uses the existing simulator test target, with new cases for manual/Health/intake precedence, every goal, invalid/nonfinite inputs, persistence, and populated version 3 migration. Exact current commands and results are recorded in OVERHAUL_STATUS.md. These tests validate implementation behavior, not clinical outcomes.
