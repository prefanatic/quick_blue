---
type: "Playbook"
title: "Maintain the knowledge bundle"
description: "Read relevant source docs before work and update and verify them with every behavior change."
tags: ["development", "agents", "okf", "documentation"]

sources: [{"id": "source1", "resource": "../AGENTS.md"}, {"id": "source2", "resource": "../CONTRIBUTING.md"}, {"id": "source3", "resource": "../quick_blue/CHANGELOG.md"}, {"id": "site", "resource": "../zensical.toml"}, {"id": "pages", "resource": "../.github/workflows/docs.yml"}]
---

# Maintain the knowledge bundle

## Before repository work

1. For read-only inquiries, open [the index](index.md) and relevant concepts.
   Before changes, also read this playbook and [testing](testing.md).
   Use this plain Markdown OKF bundle as the canonical
   detailed documentation, not the rendered website or an older README copy.
2. Trace claims to `sources` and implementation/tests. If code contradicts docs,
   establish intended behavior from tests and requirements; fix the discrepancy
   in the same change. Never change code solely to fit stale prose.
3. Before editing, inspect worktree status; preserve unrelated in-progress work,
   including active platform BLE changes. Preserve federated boundaries in root
   `AGENTS.md` and follow [generated-code rules](testing.md#native-and-generated-boundaries).

## With every change

Behavior, APIs, examples, supported platforms, setup and workflows require a
corresponding doc review. Update affected concepts in the same change, plus
index descriptions/cross-links, public README entry
points and `quick_blue/CHANGELOG.md` as applicable. In the handoff list docs
changed, or explain concretely why none were affected; do not defer maintenance
to a future documentation pass.

Follow [evidence storage](testing.md#store-reproducibility-separately-from-raw-execution-records):
reproducibility belongs in Git; raw execution records belong in durable artifacts.

Keep examples small and either runnable with their imports or explicitly labeled
fragments/placeholders. Await fallible futures or route failures to an explicit
handler; do not copy discarded async listener errors into examples.

Before committing, inspect recent commit subjects and use lower-case scoped
subjects, such as `quick_blue: tighten README docs` or
`quick_blue,platform_interface: document public APIs`.

## OKF rules used

This bundle targets **Open Knowledge Format v0.2**, re-read at specification
commit `62432a095456147ee71e70ac6e4dc0d2dea3ac30`:
[the pinned specification](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/62432a095456147ee71e70ac6e4dc0d2dea3ac30/okf/SPEC.md).

- Bundle root is `docs/`; existing root/package READMEs are outside it.
- Every concept `.md` has parseable YAML frontmatter and non-empty `type`.
  Supply concise `title`, `description`, tags and real source resources.
- `index.md` and `log.md` are reserved at every level, never concepts. Only the
  root index has frontmatter, and it carries only `okf_version: "0.2"`.
- Index entries enumerate concepts with descriptions. A separate update log is
  optional and is not maintained in this repository.
- Relative concept links are intentionally used: valid OKF, navigable directly
  on GitHub, and suitable for a site under a project URL prefix. Do not confuse
  bundle-relative `/...` with a repository-root or website-root path.
- `sources[].resource` entries use `../...` repository-relative artifacts; update
  them when source files move. Claim footnotes use their source IDs.
- Generation metadata is optional and omitted from this bundle. Add `verified`
  only after an actual content check and identify its scope; a structural lint
  is not hardware review.
  Do not manufacture human sign-offs, usage counts or test attestations.

## Validation commands

From repository root:

```sh
python3 -m venv .dart_tool/docs-venv
.dart_tool/docs-venv/bin/pip install -r scripts/requirements-docs.txt
.dart_tool/docs-venv/bin/python scripts/check-okf.py
.dart_tool/docs-venv/bin/python -m unittest discover -s scripts -p 'test_*.py'
.dart_tool/docs-venv/bin/python -O -m unittest discover -s scripts -p 'test_*.py'
.dart_tool/docs-venv/bin/zensical build --clean
.dart_tool/docs-venv/bin/python scripts/check-docs-site.py
.dart_tool/docs-venv/bin/python -O scripts/check-docs-site.py
git diff --check
```

The checker enforces this repository's quality policy (metadata, local targets,
index coverage and source-footnote joins) as well as the reserved-file rules.
OKF itself tolerates broken links and missing optional fields; this repository
chooses a stricter quality gate. External URLs are not fetched by the checker.
Review cited code/tests and exercise changed examples separately; run the site
build when site configuration is present and run [affected tests](testing.md).
Do not mark the change ready until documentation validation and relevant checks
pass, or explicitly report blockers and unverified claims.

## Preview and publish the site

After installing the toolchain above, run
`.dart_tool/docs-venv/bin/zensical serve` and open `http://localhost:8000`.
The clean build writes disposable HTML to `site/`. Edit `docs/*.md`, not the
generated HTML; keep `zensical.toml` navigation aligned with this bundle's index.
Search, syntax highlighting and code-copy controls are rendering conveniences,
not requirements for reading the source files.

The site checker requires exact navigation coverage and verifies generated local
HTML links and anchors, including the project URL prefix and search assets.
After URL decoding and directory-index selection, link targets must resolve inside
the resolved site root, including through symlinks. Parent-relative links that stay
inside the site remain valid; external URLs are not fetched.
Its critical failures use explicit exceptions, not optimization-sensitive assertions.
See [maintenance-tool regressions](testing.md#maintenance-tool-regressions) for
the hermetic suite and its proof boundaries.

The workflow `.github/workflows/docs.yml` validates OKF and builds on matching
pull requests and `master` pushes. Deployment runs only in
`prefanatic/quick_blue` on `master` (including manual dispatch on that branch),
not in a fork or on a PR. It follows the
[Zensical Pages flow](https://zensical.org/docs/publish-your-site/) with a pinned
Zensical version and no CI build cache.

A maintainer must enable Settings > Pages > Source > **GitHub Actions**, allow
Actions and the referenced actions, and allow `pages: write` and `id-token: write`
for the deployment job. The `github-pages` environment must permit `master`;
any required reviewer must approve deployment. Fork PR workflows may also need
maintainer approval before their build runs. The configured canonical URL is
`https://prefanatic.github.io/quick_blue/`; a successful local build is not
publication evidence. Confirm the deployed URL and deployment run before
claiming it is live. If the repository or domain changes, update `site_url` and
the workflow's upstream guard together.

## Release metadata

Distribution is [Git/local only](install.md#publication-compatibility-limit).
The Linux Flutter shell owns plugin metadata and its Flutter minimum; the pure
Dart backend has neither. Keep release validation enabled, but do not equate a
passing dry-run with registry name ownership, availability or an uploaded release.

All seven package manifests (including core and the Linux Dart backend) share a version.
In the same change, bump every
package's `pubspec.yaml` version and align federated constraints: each platform
package depends on `quick_blue_platform_interface` at that version and the
app-facing package pins all federated packages. The script enforces these
version/constraint invariants; it does not validate changelog headings. The separate
CI `publish-readiness` job checks that the pubspec version has a changelog heading
and fails with exit 65 when missing. That job and its dry-run are gated by the
workflow's validation path filter, not run on every prose-only change.
Fold Unreleased notes into a dated `## [x.y.z]` heading in
`quick_blue/CHANGELOG.md`, run `scripts/publish-packages.sh --dry-run` (also run by
CI), and confirm smoke tests for every reachable platform before releasing.
Real publication uses `scripts/publish-packages.sh --publish` manually and is a
separate authorized step, not part of a documentation edit.
