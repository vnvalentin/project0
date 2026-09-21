# TBP Backlog Migration Protocol

You are tasked with migrating legacy Wayfinder issues into the TBP backlog structure using the GitHub CLI. 

For every issue provided in the target scope, execute the following three phases:

### Phase 1: Taxonomy Classification
Analyze the scope of the legacy issue and map it to the correct TBP level. Apply the corresponding label using `gh issue edit <id> --add-label "<label>"`.
- Broad project/map -> `tbp:hoshin`
- Major initiative/problem space -> `tbp:theme`
- Gap analysis/deliverable -> `tbp:feature`
- Specific root cause/task group -> `tbp:epic`
- Atomic coding task/execution -> `tbp:experiment`

### Phase 2: Structural Rewrite
Extract the existing issue body and map the text into the strict TBP markdown templates (e.g., Aspirational Goal, Ideal vs. Current Condition, 4Ws). 
- Use `gh issue edit <id> --body "<new markdown>"` to overwrite the issue.
- Preserve all existing links to child/parent issues, converting them into the `- [ ]` markdown task lists required by the TBP structure.

### Phase 3: The Gap Audit
Legacy issues will be missing mandatory TBP data (e.g., the 4Ws for an Epic, or the specific Measurable Outcome for a Theme). 
- If required TBP fields cannot be safely inferred from the original text, insert `> **[TBP GAP: Needs Definition]**` under that specific heading.
- Apply a `tbp:needs-refinement` label to the issue so the user can easily query incomplete items later.