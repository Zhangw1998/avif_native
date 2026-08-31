# flutter_avif_native

Flutter widgets and image-provider integration backed by `avif_native`.

```dart
AvifImage.asset('assets/image.avif');
AvifImage.network('https://example.com/image.avif');
AvifImage.memory(bytes);
```

`AvifImage` displays still and animated AVIF frames. `AvifMemoryImage` integrates the first frame with Flutter's `ImageCache`:

```dart
Image(image: AvifMemoryImage(bytes));
```

Select the native codec profile in the application or workspace root `pubspec.yaml`:

```yaml
hooks:
  user_defines:
    avif_native:
      features: full
      decoder: dav1d
      encoder: aom
```

The package has no MethodChannel or platform registration. Native platforms are supplied by the `avif_native` build hook.
