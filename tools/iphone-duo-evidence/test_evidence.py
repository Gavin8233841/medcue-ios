import copy
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zlib
from unittest.mock import patch
import evidence as e
import run as runner


def chunk(kind, value):
    return struct.pack('>I', len(value)) + kind + value + struct.pack('>I', zlib.crc32(kind + value) & 0xffffffff)


def png(width=320, height=900, extra=b''):
    header = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    pixels = zlib.compress(b'\0' * (height * (width * 4 + 1)))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + extra + chunk(b'IDAT', pixels) + chunk(b'IEND', b'')


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.test_id = next(iter(e.EXPECTED))
        self.manifest = [{'testIdentifier': self.test_id, 'attachments': []}]
        for i, (name, width) in enumerate(e.EXPECTED[self.test_id].items()):
            filename = f'{i}.png'
            (self.root / filename).write_bytes(png(width))
            self.manifest[0]['attachments'].append({
                'exportedFileName': filename,
                'suggestedHumanReadableName': f'{name}_0_00000000-0000-0000-0000-000000000000.png',
            })

    def tearDown(self):
        self.tmp.cleanup()

    def reject(self, manifest=None):
        with self.assertRaises((e.InvalidEvidence, FileNotFoundError)):
            e.select_manifest(manifest if manifest is not None else self.manifest, self.test_id, self.root)

    def test_complete_explicit_inventory(self):
        self.assertEqual(len(e.select_manifest(self.manifest, self.test_id, self.root)), 9)

    def test_ignore_automatic_screenshot(self):
        self.manifest[0]['attachments'].append({'exportedFileName': 'does-not-exist.png', 'suggestedHumanReadableName': 'Screenshot.png'})
        self.assertEqual(len(e.select_manifest(self.manifest, self.test_id, self.root)), 9)

    def test_traversal_absolute_and_noncanonical_paths(self):
        for name in ('../escape.png', '/tmp/escape.png', 'folder/x.png', './0.png', '..', 'a\\b.png', '\n.png'):
            with self.subTest(name=name):
                value = copy.deepcopy(self.manifest)
                value[0]['attachments'][0]['exportedFileName'] = name
                self.reject(value)

    def test_symlink_rejected(self):
        (self.root / '0.png').unlink()
        (self.root / '0.png').symlink_to(self.root / '1.png')
        self.reject()

    def test_hardlink_rejected(self):
        (self.root / '0.png').unlink()
        (self.root / '0.png').hardlink_to(self.root / '1.png')
        self.reject()

    def test_symlink_root_rejected(self):
        alias = self.root / 'alias'
        alias.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(e.InvalidEvidence):
            e.safe_file(alias, '0.png')

    def test_duplicate_name_and_file_rejected(self):
        value = copy.deepcopy(self.manifest)
        value[0]['attachments'].append(copy.deepcopy(value[0]['attachments'][0]))
        self.reject(value)
        self.manifest[0]['attachments'][1]['exportedFileName'] = '0.png'
        self.reject()

    def test_missing_image_and_wrong_test_rejected(self):
        value = copy.deepcopy(self.manifest)
        value[0]['testIdentifier'] = 'Other/test()'
        self.reject(value)
        self.manifest[0]['attachments'].pop()
        self.reject()

    def test_unknown_schema_and_unknown_manual_image_rejected(self):
        value = copy.deepcopy(self.manifest)
        value[0]['newUnknownSchema'] = True
        self.reject(value)
        self.manifest[0]['attachments'][0]['suggestedHumanReadableName'] = 'MedicationDetail-secret.png'
        self.reject()

    def test_png_type_dimensions_crc_trailing_bytes(self):
        for data in (b'not PNG', png(319), png() + b'secret', png()[:-20], png().replace(b'IDAT', b'IDAX')):
            with self.subTest(size=len(data)):
                (self.root / '0.png').write_bytes(data)
                self.reject()

    def test_png_animated_and_invalid_pixels(self):
        (self.root / '0.png').write_bytes(png(extra=chunk(b'acTL', b'12345678')))
        self.reject()
        data = png()
        begin = data.index(b'IDAT') - 4
        end = begin + struct.unpack('>I', data[begin:begin+4])[0] + 12
        (self.root / '0.png').write_bytes(data[:begin] + chunk(b'IDAT', zlib.compress(b'wrong')) + data[end:])
        self.reject()

    def test_oversized_file(self):
        with (self.root / '0.png').open('wb') as file:
            file.truncate(e.LIMIT + 1)
        self.reject()

    def test_metadata_removed_from_generated_png(self):
        path = self.root / 'new.png'
        path.write_bytes(png(extra=chunk(b'tEXt', b'Comment\0private')))
        e.png_dimensions(path, 320)
        e.strip_generated_metadata(path)
        e.png_dimensions(path, 320)
        self.assertNotIn(b'private', path.read_bytes())

    def test_metadata_bomb_is_removed_before_native_decode(self):
        path, clean = self.root / 'bomb.png', self.root / 'decode.png'
        compressed_metadata = zlib.compress(b'x' * 10_000_000)
        path.write_bytes(png(extra=chunk(b'zTXt', b'key\0\0' + compressed_metadata)))
        e.prepare_decode_input(path, clean, 320)
        self.assertNotIn(b'zTXt', clean.read_bytes())
        self.assertEqual(clean.read_bytes(), png())

    def test_unknown_critical_and_duplicate_header(self):
        for extra in (chunk(b'ABCD', b''), chunk(b'IHDR', struct.pack('>IIBBBBB', 320, 900, 8, 6, 0, 0, 0))):
            (self.root / '0.png').write_bytes(png(extra=extra))
            self.reject()

    def test_invalid_scanline_filter_and_deflate(self):
        data = png()
        begin = data.index(b'IDAT') - 4
        end = begin + struct.unpack('>I', data[begin:begin+4])[0] + 12
        for payload in (b'not deflate', zlib.compress(b'\x05' + b'\0' * (900 * (320 * 4 + 1) - 1))):
            (self.root / '0.png').write_bytes(data[:begin] + chunk(b'IDAT', payload) + data[end:])
            self.reject()

    def test_noncontiguous_idat(self):
        data = png()
        iend = data.rindex(b'IEND') - 4
        (self.root / '0.png').write_bytes(data[:iend] + chunk(b'tEXt', b'key\0value') + chunk(b'IDAT', b'') + data[iend:])
        self.reject()

    def test_failure_attachment_rejected(self):
        self.manifest[0]['attachments'][0]['isAssociatedWithFailure'] = True
        self.reject()

    def test_both_native_invocations_preserve_package_and_host_boundaries(self):
        for target, class_name, methods in [
            ('MedicationAdherenceAppTests', e.DETAIL_CLASS, list(e.DETAIL)),
            ('MedicationAdherenceAppUITests', e.WINDOW_CLASS, e.WINDOW)]:
            with self.subTest(target=target):
                args = runner.native_test_command(self.root, self.root / 'test.xcresult',
                                                  '00000000-0000-0000-0000-000000000000', target, class_name, methods)
                for required in ('-disableAutomaticPackageResolution', '-skipPackageUpdates',
                                 'MEDCUE_SIMULATOR_UNIT_TEST_BUILD=YES', 'CODE_SIGNING_ALLOWED=NO'):
                    self.assertEqual(args.count(required), 1)
                packages = args[args.index('-clonedSourcePackagesDirPath') + 1]
                self.assertEqual(packages, str(self.root / 'source-packages'))
                self.assertEqual([arg for arg in args if arg.startswith('-only-testing:')],
                                 [f'-only-testing:{target}/{class_name}/{method}' for method in methods])
                self.assertFalse(any(arg in args for arg in ('-allowProvisioningUpdates', '-downloadPlatform')))

    def test_failure_diagnostics_reconstruct_only_allowlisted_fields(self):
        path = self.root / 'failure.log'
        path.write_text('/Users/private/secret/MedicationDetailAdaptiveLayoutTests.swift:359: error: '
                        'MedicationDetailAdaptiveLayoutTests.testAX5UsesOneColumnEvenInRegularWideContainer '
                        'failed: visibleAccessibilityDidNotStabilize token=SECRET UUID=DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF device=iPad Secret\n'
                        'label="patient health SECRET" polls=11, rawAX=0, visibleAX=0, sceneAttached=true\n'
                        '/Users/private/MedicationDetailView.swift:42:4: error: cannot find SECRET in scope\n')
        result = '\n'.join(e.failure_diagnostics(path))
        for forbidden in ('SECRET', 'private', '/Users', 'patient', 'DEADBEEF', 'iPad'):
            self.assertNotIn(forbidden, result)
        for required in ('MedicationDetailAdaptiveLayoutTests.swift:359', 'visibleAccessibilityDidNotStabilize',
                         'polls=11', 'rawAX=0', 'sceneAttached=true', 'Compiler category: cannot find'):
            self.assertIn(required, result)

    def test_failure_diagnostics_bounded_and_unknown_content_withheld(self):
        path = self.root / 'failure.log'
        path.write_text('PRIVATE DATA ' * 20000)
        self.assertEqual(e.failure_diagnostics(path), ['No allowlisted failure detail found; raw diagnostics remain private.'])
        path.write_text('\n'.join(f'/tmp/MedicationDetailView.swift:{i}: error: SECRET' for i in range(100)))
        result = e.failure_diagnostics(path)
        self.assertEqual(len(result), 20)
        self.assertTrue(all(len(line) <= 400 and 'SECRET' not in line for line in result))

    def test_duplicate_json_keys_rejected(self):
        with self.assertRaises(e.InvalidEvidence):
            e.decode_json(b'{"passedTests":3,"passedTests":0}')

    def result_fixture(self):
        summary = dict(passedTests=3, failedTests=0, skippedTests=0, totalTestCount=3, result='Passed')
        cases = [{'nodeType': 'Test Case', 'nodeIdentifier': identifier, 'result': 'Passed'} for identifier in e.EXPECTED]
        tree = {'testNodes': [{'nodeType': 'Test Plan', 'children': [{'nodeType': 'Unit test bundle', 'name': 'MedicationAdherenceAppTests', 'children': [{'nodeType': 'Test Suite', 'name': e.DETAIL_CLASS, 'children': cases}]}]}]}
        return summary, tree, cases

    def validate(self, summary, tree):
        e.validate_results(summary, tree, e.DETAIL_CLASS, list(e.DETAIL), 'MedicationAdherenceAppTests')

    def test_exact_passing_results(self):
        summary, tree, _ = self.result_fixture()
        self.validate(summary, tree)

    def test_skips_failures_bool_counts_missing_duplicate_wrong_id(self):
        for key, value in [('skippedTests', 1), ('failedTests', 1), ('passedTests', True), ('totalTestCount', 2), ('result', 'Failed')]:
            summary, tree, _ = self.result_fixture()
            summary[key] = value
            with self.assertRaises(e.InvalidEvidence):
                self.validate(summary, tree)
        for change in ('duplicate', 'missing', 'wrong', 'unknown', 'retry', 'failed'):
            summary, tree, cases = self.result_fixture()
            if change == 'duplicate': cases.append(cases[0])
            if change == 'missing': cases.pop()
            if change == 'wrong': cases[0]['nodeIdentifier'] = 'Other/test()'
            if change == 'unknown': cases[0]['nodeType'] = 'FutureNode'
            if change == 'retry': cases[0]['children'] = [{'nodeType': 'Repetition'}]
            if change == 'failed': cases[0]['result'] = 'Failed'
            with self.assertRaises(e.InvalidEvidence):
                self.validate(summary, tree)

    def test_unknown_runtime_schema_stops(self):
        with patch.object(e, 'command', return_value=b'unsupported help'):
            with self.assertRaises(e.InvalidEvidence):
                e.preflight()
        def output(args):
            if 'help' in args:
                return b'--path --schema --test-id --output-path'
            return b'{"type":"array"}'
        with patch.object(e, 'command', side_effect=output):
            with self.assertRaises(e.InvalidEvidence):
                e.preflight()

if __name__ == '__main__':
    unittest.main()
