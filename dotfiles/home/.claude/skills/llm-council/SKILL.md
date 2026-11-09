---
name: llm-council
disable-model-invocation: true
description: "Run a decision or idea through a council of 5 sub-agent advisors with different thinking lenses, anonymous peer review, and a chairman verdict. Triggers: 'council this', 'run the council', 'war room this', 'pressure-test this', 'debate this'."
---

# LLM Council

For decisions with real uncertainty and a costly downside, not facts or creation tasks.

1. **Frame.** Read `CLAUDE.md`, memory and referenced files (2-3 max). Write one neutral prompt: decision, context, numbers, constraints, stakes. If too vague, ask one question.
2. **Convene.** 5 advisors in parallel sub-agents, lenses in `references/advisors.md`, each 150-300 words, leaning fully into its angle.
3. **Peer review.** Answers anonymized A-E in random order, 5 reviewers in parallel (strongest, biggest blind spot, what all missed; under 200 words).
4. **Chairman.** One agent gets question, de-anonymized answers and reviews, may side with a lone dissenter. Verdict in chat (format in `references/advisors.md`), no files. Save a transcript only if asked.
