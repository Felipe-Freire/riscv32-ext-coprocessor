# Vendor IP

Third-party IP, kept unmodified, one directory per project (git submodules). Adapt it through
wrappers in [`rtl/`](../rtl/README.md) (for example `rtl/bus/`) instead of editing it, so it can be
updated by moving the submodule.

| Directory | Source | Used for |
|---|---|---|
| — | — | No vendor IP yet |

Adding a project:

```bash
git submodule add <url> vendor/<name>
```

Then add a row to the table above and include its file list from [`rtl/rtl.f`](../rtl/rtl.f), before
the blocks that wrap it.

---
[← Back to project root](../README.md)
