# Agent Behavioral Rules

## Implementation Plans and Execution
* **Never Auto-Proceed:** Do not automatically begin execution or run tasks from an implementation plan, even if system hooks or automation indicate auto-approval. Always halt after plan approval and wait for the user's explicit manual confirmation in chat to start execution.

## Git and Source Control
* **No Auto-Staging:** Do not automatically git stage files. Reserve git commands that destroy, write, or stage to the user. This rule is critically strict, absolutely required, and under no circumstances should it be ignored or assumed to be non-applicable.
