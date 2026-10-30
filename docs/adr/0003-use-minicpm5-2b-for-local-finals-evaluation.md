# ADR-0003: Use MiniCPM5-2B For Local Finals Evaluation

- Status: Adopted in the local finals working tree; not integrated or released
- Date: 2026-10-28
- Scope: Controlled physical-device demonstration and local evaluation
- Decision: Owner authorized model repair, relaxed style checks, the 2B trial and a thinking-mode comparison. Direct mode is the engineering default based on the observed comparison; owner/UI acceptance remains separate.

## Context

The MiniCPM4-0.5B candidate suffered both implementation defects and genuine output-quality problems. Keyword/style checks rejected ordinary wording and English drug names; title filtering could remove the answer, and generic questions were misrouted into trend summaries. Device probes also exposed invented doses, weather and inventory details. Removing rejection alone made more outputs visible without establishing their correctness.

## Decision

- Select official MiniCPM5-2B Q4_K_M for the current local build, with direct answering as default. Keep thinking mode available for explicit testing through the existing parser and reasoning disclosure path; do not default to it on the evidence below.
- Use the [official Apache-2.0 model](https://huggingface.co/openbmb/MiniCPM5-2B-GGUF), pinned to revision `2079a22f3beaa4e306449978533478fe0522f4b3`. File: `MiniCPM5-2B-Q4_K_M.gguf`; size: 1,561,318,368 bytes; SHA-256: `ec2d5801640099e97d8d7e8003ad4d81f336e757811f03a26173dddf386602fd`. Keep weights outside Git and source packages. Preserve the older installed model.
- Allow English names, headings, lists and normal phrasing. Do not require topic keyword hits or arbitrary sentence/character cutoffs. Keep checks for unreadable machine output and actionable treatment instructions, and retain finalization before display/persistence.
- Do not use fixed-answer fallbacks to claim model improvement. That experiment was rejected by the owner and removed.
- Apply the model chat template with special-token parsing, avoid duplicate sampler acceptance, release contexts before models, and restore a prefilled thinking opener for stream parsing. Reuse the existing current-request/cancellation mechanism and thinking/answer separation informed by the read-only CatPaw reference; do not import its whole UI or change consent boundaries.

## Alternatives And Evidence

- Continued tuning of MiniCPM4-0.5B: implementation repairs reduced repetition and false rejection but manual device review still found fabricated facts.
- Qwen2.5-1.5B: prepared as an older comparison candidate, not established as best and not selected. Current-model research instead prioritized MiniCPM5-2B; MiniCPM5-1B remains a smaller untested alternative.
- MiniCPM5-2B direct: 35/35 synthetic device cases generated and passed the current boundary checks, approximately 0.49–3.50 seconds. This includes built-in prompts with empty and synthetic contexts and English-name questions. Manual review found better grounding; some answers remained terse or confused record details with label fields. This is not 35/35 factual accuracy.
- MiniCPM5-2B thinking: 4/5 empty-context built-in cases completed; successful cases took approximately 5.20–11.94 seconds, with one `boundary-or-empty` failure. The observed sample did not justify the added latency as default. It is not an exhaustive comparison.

## Validation And Limits

Evidence belongs to `codex/finals-baseline-integration` based on `9d0892ae2787c32f655399a42c8ac8e612aebf02` plus uncommitted source, not that commit alone. Device builds/install/inference and a final default-path smoke succeeded. Local policy/parser harness: 21 tests passed using exact source copies and a model-label stub, without llama inference. Simulator XCTest failed to establish its runner connection; it is not claimed passed. Quick checks and independent source review passed for the implementation scope.

The existing reasoning UI was inspected, not manually accepted on device. Real-data correctness, broader device/memory/thermal behavior, full native gate, current-revision CI, integration and release remain unconfirmed. Build logs may contain device identifiers and must remain local/redacted when shared. Synthetic raw model output is local diagnostic evidence, not user health data.

## Evidence Pointers

Local ignored evidence root: `.codex-local/local-ai-repair-20261028/round2/`:

- `minicpm5-direct-final-synthetic-output.txt`: 35 direct cases and answers.
- `minicpm5-thinking-synthetic-output.txt`: five thinking cases and reasoning.
- `active-final-synthetic-output.txt`: final default path identifies MiniCPM5-2B and completes, followed by successful normal launch.
- `harness-tests.log`, `policy-harness/source-hashes.json`, `quick-final.log`, `final-source-hashes.json`: bounded checks and source fingerprints.

These files are not guaranteed to exist in a clean clone. Current engineering truth remains in [PROJECT_STATUS.md](../PROJECT_STATUS.md); this ADR records the model-selection decision and its trade-offs.
