# Changelog

<!-- Format guidelines: https://keepachangelog.com/en/1.1.0/#how -->

## Unreleased

<!--
When you make changes without bumping the version right away, document them here.
If that's not something you ever plan to do, consider removing this section.
-->

*Nothing yet.*

## 0.7.1

- Hermeto release - <https://github.com/hermetoproject/hermeto/releases/tag/0.60.1>
- Fixes [GHSA-rfhj-wcpf-9jcx](https://github.com/hermetoproject/hermeto/security/advisories/GHSA-rfhj-wcpf-9jcx)
- Fixes [GHSA-rpww-j58f-22xr](https://github.com/hermetoproject/hermeto/security/advisories/GHSA-rpww-j58f-22xr)
- Fixes [GHSA-pxcg-wp85-mcrg](https://github.com/hermetoproject/hermeto/security/advisories/GHSA-pxcg-wp85-mcrg)
- Fixes [GHSA-wx26-fvpq-v9rp](https://github.com/hermetoproject/hermeto/security/advisories/GHSA-wx26-fvpq-v9rp)

### Added

- Added optional `pip-index-url` parameter to pass `PIP_INDEX_URL` to Hermeto for pip dependency prefetch.
  When set, this URL is used as a fallback package index when `requirements.txt` does not specify `--index-url`.
  To use this parameter, add `pip-index-url` (type: string, default: `""`) to your pipeline params
  and pass it to the prefetch-dependencies task.

## 0.7.0

- Hermeto release - <https://github.com/hermetoproject/hermeto/releases/tag/0.60.0>
- The `.repo` file for RPM dependencies is now named `hermeto.repo` instead of `cachi2.repo`

## 0.6.0

- Hermeto release - <https://github.com/hermetoproject/hermeto/releases/tag/0.59.0>

## 0.5.0

- Hermeto release - <https://github.com/hermetoproject/hermeto/releases/tag/0.58.0>

## 0.4.1

*Version 0.4.1 only changes the `-oci-ta` variant of this task.
Nothing changed in the base task (the one you're looking at).*

## 0.4.0

- Hermeto releases from 0.55.0 to 0.57.1 - <https://github.com/hermetoproject/hermeto/compare/0.55.0...0.57.1>

## 0.3.2

- Added `enable-package-registry-proxy` parameter to enable use of the package registry proxy when prefetching dependencies.
- Added `SERVICE_CA_TRUST_CONFIG_MAP_NAME` and `SERVICE_CA_TRUST_CONFIG_MAP_KEY` parameters to mount the OpenShift service CA for verifying TLS connections to in-cluster services such as the package registry proxy.

## 0.3.1

### Added

- In addition to the `cachi2.env` file, the output directory will also have
  a `prefetch.env` file.
  - Both files have the same content, `prefetch.env` is the primary one.
    `cachi2.env` stays for now, for backwards compatibility with existing Tasks.
- In addition to the `*.env` files, the output directory will also have
  a `prefetch-env.json` file.
  - This will enable future versions of the buildah Task to inject prefetch environment
    variables without any invasive editing of the containerfile.

## 0.3

- Removed deprecated `dev-package-managers` parameter.
- Switched from bash implementation to Konflux Build CLI.
