# Changelog

<!-- Format guidelines: https://keepachangelog.com/en/1.1.0/#how -->

## Unreleased

<!--
When you make changes without bumping the version right away, document them here.
If that's not something you ever plan to do, consider removing this section.
-->

*Nothing yet.*

## 0.3

### Added

- BREAKING: new required parameter: `BINARY_IMAGE_DIGEST`.

  For pipelines that include the `build-image-index` task, pass its result to this param:

  ```yaml
  - name: BINARY_IMAGE_DIGEST
    value: "$(tasks.build-image-index.results.IMAGE_DIGEST)"
  ```

  For those that don't, pass the result from the `build-container` task instead:

  ```yaml
  - name: BINARY_IMAGE_DIGEST
    value: "$(tasks.build-container.results.IMAGE_DIGEST)"
  ```

  *Note: the MintMaker PR updating source-build to v0.3 should apply these changes automatically.*

- Started tracking changes in this file.
