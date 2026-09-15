# CLAUDE.md

Behavioral guidelines for working in this codebase. These reflect how I
write code. Match them.

## Comments

Do not write comments. Code should be clear enough that comments are
unnecessary. A comment that restates what the code does is a code smell; if
you feel the need to explain a block of code, rewrite the code until the
explanation is redundant.

Doc comments are the exception, and they serve a different purpose. Write
documentation from the user's perspective: how do I use this thing? What
does it do for me? What are the inputs, outputs, and failure modes? Include
examples in doc comments; examples are documentation, not restatement. Never
use doc comments to narrate the implementation.

## Style

I am a functional programmer. Write code accordingly:

- Small building blocks that compose. Prefer many small, reusable functions
  over few large ones.
- Build combinator libraries, then compose and combine functionality from
  them. When you see repeated structure, extract the combinator.
- Prefer pure functions. Push effects to the edges.
- Prefer expressions over statements, transformation over mutation, and
  making invalid states unrepresentable over runtime checks.

## Architecture

Use hexagonal architecture for full applications:

- The core domain is pure functions. It should be trivially testable with no
  mocks, no IO, no setup ceremony.
- IO and side effects live in the outer layer: adapters for the database,
  network, filesystem, clock, whatever the application touches.
- Implement the outer layer using the best idiomatic method for the language
  at hand. The core stays pure everywhere; the adapters are allowed to look
  like the language they are written in.

## Organization

Writing code is organizing your thoughts, like physically cleaning a room.
Everything should have a place, and everything should be in its place.

When something feels like it doesn't have a place, that is the signal to
stop. Do not force it into the nearest file or bolt it onto an existing
module. Stop and think about how to organize. Time spent on organization is
not overhead; it pays for itself down the line.

Apply the same rule to your own work: if you are unsure where new code
belongs, raise it and propose an organization rather than guessing.

## Fixes

Prefer correct solutions over hacks. A workaround that creates downstream
consequences is worse than taking longer to do it right. If a correct fix is
out of scope, say so explicitly instead of quietly shipping the hack.

## Git

Commit as the local user. Do not sign commits as Claude or add Claude
attribution to commit messages.
