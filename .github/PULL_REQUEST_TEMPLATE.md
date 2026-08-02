<!-- Thanks for contributing to Porter! Fill in the sections below — it makes review fast. -->

## Summary

<!-- What does this PR do, and why? One or two sentences. -->

## Type of change

<!-- Check exactly the ones that apply. -->

- [ ] 🐛 **Fix** — corrects a bug (describe the broken behavior below)
- [ ] 🩹 **Patch** — small correction to a recent change / hotfix
- [ ] ✨ **Feature** — new capability (new format, new engine, new UI)
- [ ] ♻️ **Refactor** — no behavior change, code structure only
- [ ] 🧹 **Chore** — tooling, build scripts, dependencies, cleanup
- [ ] 📝 **Docs** — README, comments, templates
- [ ] ⚙️ **CI** — workflows, test infrastructure

## Related issue

<!-- e.g. "Fixes #12" or "N/A" -->

Fixes #

## What changed

<!-- Bullet list of the concrete changes. For fixes: what was broken, root cause, and the fix. -->

-

## How to test / reproduce

<!-- Exact steps a reviewer can run. For bug fixes, include steps that reproduce
     the bug BEFORE this change, so the fix is verifiable. -->

```sh
make build
# e.g.: porter path/to/sample.docx  →  expect sample.pdf next to it
```

**For conversion changes, state which file type(s) and engine(s) you tested with**
(e.g. "legacy .doc via Word 16.89", ".pptx via PowerPoint"):

-

## Screenshots

<!-- Required for any UI change (drop zone, settings, icons). Delete if N/A. -->

## Checklist

- [ ] `make test-native` passes locally
- [ ] `make test` passes (needs MS Office) — **or** I've listed the engines I couldn't test above
- [ ] New behavior is covered by a test in `test.sh` (new formats need a fixture or a generated sample)
- [ ] README updated if usage, formats, or settings changed
- [ ] No build artifacts or personal paths committed (`build/` stays untracked)
