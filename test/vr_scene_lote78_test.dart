import 'package:flutter_scene/scene.dart' as fs;
import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_scene/src/assets/vr_glb_template_cache.dart';

void main() {
  test('VrGlbTemplateCache rejects path traversal, external schemes, leading slash, and extreme texture sizes', () async {
    expect(() => VrGlbTemplateCache(maxEntries: 0), throwsArgumentError);
    var calls = 0;
    final cache = VrGlbTemplateCache(
      loader: (_, {maxTextureSize}) async {
        calls++;
        return fs.Node();
      },
    );
    addTearDown(cache.dispose);

    await expectLater(cache.instantiate(' '), throwsArgumentError);
    await expectLater(cache.instantiate('../secret.glb'), throwsArgumentError);
    await expectLater(cache.instantiate('models/../../secret.glb'), throwsArgumentError);
    await expectLater(cache.instantiate('/etc/passwd'), throwsArgumentError);
    await expectLater(cache.instantiate('https://evil.example/a.glb'), throwsArgumentError);
    await expectLater(cache.instantiate('models\\evil.glb'), throwsArgumentError);
    await expectLater(cache.instantiate('models/a\u202E.glb'), throwsArgumentError);
    await expectLater(cache.instantiate('a.glb', maxTextureSize: 0), throwsArgumentError);
    await expectLater(cache.instantiate('a.glb', maxTextureSize: 32768), throwsArgumentError);
    expect(calls, 0);

    final ok = await cache.instantiate('assets/models/avatar.glb', maxTextureSize: 1024);
    expect(ok.parent, isNull);
    expect(calls, 1);
  });
}
