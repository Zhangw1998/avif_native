# Publishing to pub.dev

Published packages are prepared in a temporary directory. The preparation step removes the monorepo-only `publish_to: none` and `resolution: workspace` fields and rejects local or incomplete native manifests.

## First release: manual

The native release must exist before publishing `avif_native`. Its immutable release manifest is checked in at `packages/avif_native/native/manifest.json`.

```sh
dart pub login

tool/publish_package.sh avif_native --dry-run
tool/publish_package.sh avif_native --publish
```

Wait until `https://pub.dev/packages/avif_native` shows the new version, then publish the dependent Flutter package:

```sh
tool/publish_package.sh flutter_avif_native --dry-run
tool/publish_package.sh flutter_avif_native --publish
```

Versions on pub.dev are immutable. Do not push pub publishing tags for this first manual version.

## Later releases: GitHub OIDC

After the first manual release, open the **Automated publishing** settings for each package on pub.dev and configure:

| Package | GitHub repository | Tag pattern |
| --- | --- | --- |
| `avif_native` | `Zhangw1998/avif_native` | `avif_native-v{{version}}` |
| `flutter_avif_native` | `Zhangw1998/avif_native` | `flutter_avif_native-v{{version}}` |

The workflow at `.github/workflows/pub-publish.yml` tests, stages, and publishes the package with GitHub OIDC. The tag version must exactly match the package pubspec version.

Publish the core package first and wait for it to become available before tagging the Flutter package:

```sh
git tag avif_native-v0.1.1
git push origin avif_native-v0.1.1

# After avif_native 0.1.1 appears on pub.dev:
git tag flutter_avif_native-v0.1.1
git push origin flutter_avif_native-v0.1.1
```

If native binaries changed, publish `native-v<version>` first, copy its generated `manifest.json` into the core package, and only then create the pub tag.
