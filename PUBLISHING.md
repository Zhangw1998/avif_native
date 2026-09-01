# Publishing

The first release was published manually. Later releases use GitHub OIDC.

One-time pub.dev package admin setting:

- Repository: `Zhangw1998/avif_native`
- Tag pattern: `v{{version}}`

For a Dart-only release, update `version` in `pubspec.yaml` and `CHANGELOG.md`, commit to `main`, wait for CI, then push the matching tag:

```sh
git tag v0.1.1
git push origin v0.1.1
```

If native code or dependencies changed, first run the `Native release` workflow with the same native version and replace `native/manifest.json` with the generated release manifest. A Dart-only release may reuse an older formal native manifest.

The publish workflow tests the package and uses GitHub OIDC, so no pub.dev token is stored in GitHub.
