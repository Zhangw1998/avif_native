import 'dart:convert';
import 'dart:io';

const packages = {'avif_native', 'flutter_avif_native'};
const profiles = {
  'decode-dav1d',
  'encode-aom',
  'full-aom-aom',
  'full-dav1d-aom',
};
const targets = {
  'android-arm',
  'android-arm64',
  'android-x64',
  'ios-device-arm64',
  'ios-simulator-arm64',
  'ios-simulator-x64',
  'linux-arm64',
  'linux-x64',
  'macos-arm64',
  'macos-x64',
  'windows-x64',
};

void main(List<String> args) {
  if (args.length != 1 || !packages.contains(args.single)) {
    stderr.writeln('usage: dart run tool/prepare_publish.dart <package>');
    exitCode = 64;
    return;
  }

  final name = args.single;
  final source = Directory('packages/$name').absolute;
  final destination = Directory.systemTemp.createTempSync('$name-publish-');

  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    if (relative
        .split(Platform.pathSeparator)
        .any({'.dart_tool', 'build', 'pubspec.lock'}.contains)) {
      continue;
    }
    final output = _path(destination.path, relative);
    if (entity is Directory) {
      Directory(output).createSync(recursive: true);
    } else if (entity is File) {
      File(output)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
  }

  final pubspec = File(_path(destination.path, 'pubspec.yaml'));
  final original = pubspec.readAsStringSync();
  final version = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(original)!.group(1)!;
  pubspec.writeAsStringSync(
    original
        .split('\n')
        .where(
          (line) =>
              line.trim() != 'publish_to: none' &&
              line.trim() != 'resolution: workspace',
        )
        .join('\n'),
  );
  File(
    _path(destination.path, '.pubignore'),
  ).writeAsStringSync('.dart_tool/\nbuild/\npubspec.lock\n');

  if (name == 'avif_native') {
    _verifyManifest(destination, version);
  }
  stdout.writeln(destination.path);
}

void _verifyManifest(Directory package, String version) {
  final manifest =
      jsonDecode(
            File(
              _path(package.path, 'native/manifest.json'),
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  if (manifest['nativeVersion'] != version) {
    throw StateError('Package and native manifest versions must match');
  }

  final artifacts = manifest['artifacts'] as Map<String, Object?>;
  final missing = {
    for (final target in targets)
      for (final profile in profiles) '$target-$profile',
  }.difference(artifacts.keys.toSet());
  if (missing.isNotEmpty) {
    throw StateError('Native manifest is missing: ${missing.join(', ')}');
  }

  final hash = RegExp(r'^[0-9a-f]{64}$');
  for (final entry in artifacts.entries) {
    final artifact = entry.value as Map<String, Object?>;
    if (artifact.containsKey('path') ||
        !(artifact['url'] as String? ?? '').startsWith('https://') ||
        !hash.hasMatch(artifact['archiveSha256'] as String? ?? '') ||
        !hash.hasMatch(artifact['librarySha256'] as String? ?? '')) {
      throw StateError('Invalid release artifact: ${entry.key}');
    }
  }
}

String _path(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';
