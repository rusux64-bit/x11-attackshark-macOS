# AGENTS.md

## Git & Workflow Rules

1. Modify files LOCALLY ONLY. NEVER run `git commit` or `git push` automatically.
2. When changes are complete, present a clear summary and propose a commit message in Conventional Commits format.
3. Always wait for my explicit confirmation before running the commit command.
4. Git is configured with an SSH signing key, so any approved commit will be signed automatically.

## Coding Principles (Karpathy Guidelines)

Behavioral guidelines to reduce common LLM coding mistakes. These favor caution over speed; for trivial tasks, use judgment.

### 1. Think Before Coding

Don't assume. Don't hide confusion. Surface tradeoffs.

- State your assumptions explicitly. If uncertain, ask instead of guessing.
- If multiple interpretations exist, present them. Don't pick one silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop, name what's confusing, and ask.

### 2. Simplicity First

Write the minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If 200 lines could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

Touch only what you must. Clean up only your own mess.

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match the existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it. Don't delete it.

When your changes create orphans:
- Remove imports, variables, and functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: every changed line should trace directly to my request.

### 4. Goal-Driven Execution

Define success criteria. Loop until verified.

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass."
- "Fix the bug" → "Write a test that reproduces it, then make it pass."
- "Refactor X" → "Ensure tests pass before and after."

For multi-step tasks, state a brief plan:

1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

### Signs These Guidelines Are Working

- Fewer unnecessary changes in diffs.
- Fewer rewrites caused by overcomplication.
- Clarifying questions come before implementation, not after mistakes.

