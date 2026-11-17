import pathlib
import plistlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'ci'))
from verify_bundle import validate_build_version


class BundleVersionTests(unittest.TestCase):
    def test_rejects_numeric_plist_build_version(self):
        # Unquoted YAML build numbers survive plist generation as integers,
        # which App Store Connect reports as an empty CFBundleVersion.
        info = plistlib.loads(plistlib.dumps({'CFBundleVersion': 5}))
        with self.assertRaisesRegex(ValueError, 'CFBundleVersion'):
            validate_build_version(info, 'LightRetro.app')

    def test_accepts_string_plist_build_versions(self):
        for version in ('1', '5', '17.2', '17.2.3'):
            with self.subTest(version=version):
                info = plistlib.loads(plistlib.dumps({'CFBundleVersion': version}))
                validate_build_version(info, 'LightRetro.app')

    def test_rejects_missing_or_malformed_versions(self):
        for version in (None, '', True, 5.0, ' 5', '5\n', '1.2.3.4', 'build-5', '$(BUILD_NUMBER)'):
            with self.subTest(version=version), self.assertRaises(ValueError):
                validate_build_version({'CFBundleVersion': version}, 'LightRetro.app')
        with self.assertRaises(ValueError):
            validate_build_version({}, 'LightRetro.app')


if __name__ == '__main__':
    unittest.main()
