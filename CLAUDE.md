# Notes for Claude Code sessions in this repository

- `documentation_rules.md` is the house style for every guide; read it before
  editing documentation.
- `PUBLISHING.md` is the release runbook. Follow it step by step rather than
  from memory.
- Recording a newly minted Zenodo DOI (the identifier table in `PUBLISHING.md`,
  the changelog) is a markdown-only edit: commit it straight to `main`, without
  a pull request and without a local test run. The CI run on `main` is the
  check. See "The citable identifiers" in `PUBLISHING.md`.
