---
name: Creative studio scope
description: User-confirmed audience and architecture approval boundaries for the iOS creative studio.
---

The first release serves short-form social creators. After reviewing the comparison, the user explicitly approved Swift native for the bounded capture-to-export experiment.

**Why:** The user explicitly answered the product-direction questions this way.

**How to apply:** Use Swift for the experiment; do not treat this as approval to build the full application.

The user reports an iPhone 16 and iPhone 15 Pro, “iOS 27,” and an available Apple account with signing setup needed. They explicitly clarified: “Do not have a mac.” Exact OS builds and any alternative build/profiling access remain unconfirmed.

**Why:** Willingness to follow instructions was mistakenly treated as confirmation of Mac access; the user corrected that assumption.

**How to apply:** Keep native build/profiling validation blocked until an access path is explicitly confirmed. Mac instructions are a future collaborator handoff, not immediately actionable user steps. Do not infer paid access approval or switch architecture without consent.

The user requires discussion of feasibility, architecture and limitations before coding. Do not generate the whole application in one attempt or present a superficial UI-only prototype as complete. Meaningful offline functionality and real editing, rendering, capture and media processing are product requirements.

**Why:** These are explicit standing constraints in the user's project brief.

**How to apply:** Keep native capability validation separate from interface previews; identify untested hardware-dependent behavior honestly.
