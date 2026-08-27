# Foregrounding the App to Escape the Apple FM Rate Limit

Dictus will not bring DictusApp to the foreground in order to run a polish or Smart Mode call. Not per dictation, not periodically, not automatically.

## Why this is out of scope

Apple documents that `rateLimited` only occurs for apps running in the background, and a controlled test on 2026-08-13 (#315) showed the rule is applied per call: the same process, seconds apart, is refused backgrounded and served in the foreground. So foregrounding does work. It is rejected on cost, not on effect.

DictusApp is backgrounded by design. The keyboard extension holds the screen, the app records and transcribes behind it, and the user never sees DictusApp during normal use. The one moment the product does foreground the app — cold-start dictation — is the worst moment in it, and it has three open issues to itself (#23 no API exists to return the user, #264 the home-screen flash, #311 the stranded dictation on an early swipe-back). Doing that after every dictation would apply the product's worst interaction to its most common one.

A periodic variant was considered — foreground every twenty or thirty minutes to reset the budget — and fails on its own terms: the test showed a foreground visit does not refund the budget at all. Only a process restart does, and an app cannot restart itself.

## What is in scope instead

Moving the call to a process that is already in the foreground: the keyboard extension. Measured separately. Failing that, honest degradation, and a backend not subject to foreground priority (#268, #351).
