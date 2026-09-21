# Choose an AI model for HQ work

Tiny Farm HQ keeps each card and seat's assigned model. The execution policy
chooses the provider and actual model when the work starts. The policy lives in
`hq/data/execution_policy.json` and is read again for every launch.

## Current temporary routing

HQ is in `codex` mode. Its original assignments use these temporary Codex
models:

| Original assignment | Model that runs |
| --- | --- |
| Fable | `gpt-6-astra` |
| Opus | `gpt-5.6-sol` |
| Sonnet | `gpt-5.6-terra` |
| Haiku | `gpt-5.6-luna` |

The card still records its original assignment. Session records keep both that
requested model and the provider/model that actually ran, so changing the
temporary route does not rewrite an assignment.

## Run the one approved trial

Background work is paused. Automatic queue work, capture, preparation,
replies, deadlines, animation, and ordinary drain launches do not start a
model while `background_paused` is `true`.

The pause blocks automatic launches only. A supervised launch is limited to
the card named by `trial_item` and may run only its build-worker and checker
phases; no other card can use supervised execution. This policy currently
nominates `w85a6cc7505a`.

Explicit interactive launches and `writing_hook` launches remain allowed while
background work is paused. Interactive means work a person explicitly starts,
not background work relabeled as interactive. Writing hooks remain available
so reviewed commits can run their writing check.

## Watch the model that ran

Open **The bullpen** in HQ. Each worker and checker session identifies the
provider and actual model. When temporary routing changed an assignment, the
same line also shows the original assigned model in parentheses.

## Restore native Claude deliberately

Set `mode` to `claude` in `hq/data/execution_policy.json`. Leave seat and card
assignments unchanged: Fable, Opus, Sonnet, and Haiku then run as their native
Claude assignments. An explicit GPT model remains an explicit Codex request;
remove or replace such an override if the work should return to Claude.

Changing `mode` does not unpause background work. Change
`background_paused` separately only when automatic launches are authorized.
