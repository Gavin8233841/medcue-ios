import copy
import json
import io
from contextlib import redirect_stdout, ExitStack
from pathlib import Path
import struct
import tempfile
import unittest
import zlib
from unittest.mock import patch, Mock
import evidence as e
import run as runner

# Real STATIC SDK-only schemas, run37881518599/job113662042845. No result data.
# Provenance timestamps and original digests are in README.
SDK_SCHEMAS = json.loads(r'''{"summary":{"schemas":{"Configuration":{"properties":{"configurationId":{"type":"string"},"configurationName":{"type":"string"}},"required":["configurationId","configurationName"],"type":"object"},"Device":{"properties":{"architecture":{"type":"string"},"deviceId":{"type":"string"},"deviceName":{"type":"string"},"modelName":{"type":"string"},"osBuildNumber":{"type":"string"},"osVersion":{"type":"string"},"platform":{"type":"string"}},"required":["deviceId","deviceName","architecture","modelName","osVersion"],"type":"object"},"DeviceAndConfigurationSummary":{"properties":{"device":{"$ref":"#/schemas/Device"},"expectedFailures":{"type":"integer"},"failedTests":{"type":"integer"},"passedTests":{"type":"integer"},"skippedTests":{"type":"integer"},"testPlanConfiguration":{"$ref":"#/schemas/Configuration"}},"required":["device","testPlanConfiguration","passedTests","failedTests","skippedTests","expectedFailures"],"type":"object"},"InsightSummary":{"properties":{"category":{"type":"string"},"impact":{"type":"string"},"text":{"type":"string"}},"required":["impact","category","text"],"type":"object"},"Statistic":{"properties":{"subtitle":{"type":"string"},"title":{"type":"string"}},"required":["title","subtitle"],"type":"object"},"Summary":{"properties":{"devicesAndConfigurations":{"$ref":"#/schemas/DeviceAndConfigurationSummary"},"environmentDescription":{"description":"Description of the Test Plan, OS, and environment that was used during testing","type":"string"},"expectedFailures":{"type":"integer"},"failedTests":{"type":"integer"},"finishTime":{"description":"Date as a UNIX timestamp (seconds since midnight UTC on January 1, 1970)","format":"double","type":"number"},"passedTests":{"type":"integer"},"result":{"$ref":"#/schemas/TestResult"},"skippedTests":{"type":"integer"},"startTime":{"description":"Date as a UNIX timestamp (seconds since midnight UTC on January 1, 1970)","format":"double","type":"number"},"statistics":{"items":{"$ref":"#/schemas/Statistic"},"type":"array"},"testFailures":{"$ref":"#/schemas/TestFailure"},"title":{"type":"string"},"topInsights":{"items":{"$ref":"#/schemas/InsightSummary"},"type":"array"},"totalTestCount":{"type":"integer"}},"required":["title","environmentDescription","topInsights","result","totalTestCount","passedTests","failedTests","skippedTests","expectedFailures","statistics","devicesAndConfigurations","testFailures"],"type":"object"},"TestFailure":{"properties":{"failureText":{"type":"string"},"targetName":{"type":"string"},"testIdentifier":{"deprecated":true,"description":"This field is deprecated. Please use testIdentifierString or testIdentifierURL.","format":"int64","type":"integer"},"testIdentifierString":{"type":"string"},"testIdentifierURL":{"type":"string"},"testName":{"type":"string"}},"required":["testName","targetName","failureText","testIdentifier","testIdentifierString"],"type":"object"},"TestResult":{"enum":["Passed","Failed","Skipped","Expected Failure","unknown"],"type":"string"}}},"tests":{"schemas":{"Configuration":{"properties":{"configurationId":{"type":"string"},"configurationName":{"type":"string"}},"required":["configurationId","configurationName"],"type":"object"},"Device":{"properties":{"architecture":{"type":"string"},"deviceId":{"type":"string"},"deviceName":{"type":"string"},"modelName":{"type":"string"},"osBuildNumber":{"type":"string"},"osVersion":{"type":"string"},"platform":{"type":"string"}},"required":["deviceId","deviceName","architecture","modelName","osVersion"],"type":"object"},"TestNode":{"properties":{"children":{"items":{"$ref":"#/schemas/TestNode"},"type":"array"},"details":{"type":"string"},"duration":{"description":"Human-readable duration with optional components of days, hours, minutes and seconds","type":"string"},"durationInSeconds":{"description":"Time interval in seconds","format":"double","type":"number"},"name":{"type":"string"},"nodeIdentifier":{"type":"string"},"nodeIdentifierURL":{"type":"string"},"nodeType":{"$ref":"#/schemas/TestNodeType"},"result":{"$ref":"#/schemas/TestResult"},"tags":{"items":{"type":"string"},"type":"array"}},"required":["nodeType","name"],"type":"object"},"TestNodeType":{"enum":["Test Plan","Unit test bundle","UI test bundle","Test Suite","Test Case","Device","Test Plan Configuration","Arguments","Repetition","Test Case Run","Failure Message","Source Code Reference","Attachment","Expression","Test Value","Runtime Warning"],"type":"string"},"TestResult":{"enum":["Passed","Failed","Skipped","Expected Failure","unknown"],"type":"string"},"Tests":{"properties":{"devices":{"items":{"$ref":"#/schemas/Device"},"type":"array"},"testNodes":{"items":{"$ref":"#/schemas/TestNode"},"type":"array"},"testPlanConfigurations":{"items":{"$ref":"#/schemas/Configuration"},"type":"array"}},"required":["testPlanConfigurations","devices","testNodes"],"type":"object"}}}}''')


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
        for i, (name, dimensions) in enumerate(e.EXPECTED[self.test_id].items()):
            filename = f'{i}.png'
            (self.root / filename).write_bytes(png(*min(dimensions)))
            self.manifest[0]['attachments'].append({
                'exportedFileName': filename,
                'suggestedHumanReadableName': f'{name}_0_00000000-0000-0000-0000-000000000000.png',
                'isAssociatedWithFailure': False,
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
        e.png_dimensions(path, {(320, 900)})
        e.strip_generated_metadata(path)
        e.png_dimensions(path, {(320, 900)})
        self.assertNotIn(b'private', path.read_bytes())

    def test_metadata_bomb_is_removed_before_native_decode(self):
        path, clean = self.root / 'bomb.png', self.root / 'decode.png'
        compressed_metadata = zlib.compress(b'x' * 10_000_000)
        path.write_bytes(png(extra=chunk(b'zTXt', b'key\0\0' + compressed_metadata)))
        e.prepare_decode_input(path, clean, {(320, 900)})
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

    def test_all_native_invocations_preserve_package_and_host_boundaries(self):
        for target, class_name, methods in [
            ('MedicationAdherenceAppTests', e.DETAIL_CLASS, list(e.DETAIL)),
            ('MedicationAdherenceAppUITests', e.WINDOW_CLASS, e.WINDOW),
            ('MedicationAdherenceAppUITests', e.AX_CLASS, list(e.AX))]:
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
        detail_source = self.root / 'private' / 'MedicationDetailAdaptiveLayoutTests.swift'
        view_source = self.root / 'MedicationDetailView.swift'
        self.assertTrue(detail_source.is_absolute())
        path.write_text(f'{detail_source}:359: error: '
                        'MedicationDetailAdaptiveLayoutTests.testAX5UsesOneColumnEvenInRegularWideContainer '
                        'failed: visibleAccessibilityDidNotStabilize token=SECRET UUID=DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF device=iPad Secret\n'
                        'label="patient health SECRET" polls=11, rawAX=0, visibleAX=0, sceneAttached=true\n'
                        f'{view_source}:42:4: error: cannot find SECRET in scope\n')
        result = '\n'.join(e.failure_diagnostics(path))
        for forbidden in ('SECRET', 'private', str(self.root), str(detail_source), str(view_source), 'patient', 'DEADBEEF', 'iPad'):
            self.assertNotIn(forbidden, result)
        for required in ('MedicationDetailAdaptiveLayoutTests.swift:359', 'visibleAccessibilityDidNotStabilize',
                         'polls=11', 'rawAX=0', 'sceneAttached=true', 'Compiler category: cannot find'):
            self.assertIn(required, result)

    def test_failure_diagnostics_bounded_and_unknown_content_withheld(self):
        path = self.root / 'failure.log'
        path.write_text('PRIVATE DATA ' * 20000)
        self.assertEqual(e.failure_diagnostics(path), ['No allowlisted failure detail found; raw diagnostics remain private.'])
        path.write_text('\n'.join(f'{self.root / "MedicationDetailView.swift"}:{i}: error: SECRET' for i in range(100)))
        result = e.failure_diagnostics(path)
        self.assertEqual(len(result), 20)
        self.assertTrue(all(len(line) <= 400 and 'SECRET' not in line for line in result))

    def test_schema_diagnostics_only_invoke_static_no_bundle_commands(self):
        calls = []
        def output(args):
            calls.append(args)
            self.assertEqual(args[:4], ['xcrun', 'xcresulttool', 'get', 'test-results'])
            self.assertIn(args[4], ('summary', 'tests'))
            self.assertEqual(args[5:], ['--schema'])
            if '--schema' not in args or '--path' in args:
                return b'{"privateResult":"DO_NOT_PRINT_RUNTIME_CONTENT"}'
            return json.dumps({'$ref': '#/definitions/StaticSDKType', 'definitions': {'StaticSDKType': {'type': 'object'}}}).encode()
        captured = io.StringIO()
        with patch.object(e, 'command', side_effect=output), redirect_stdout(captured):
            with self.assertRaisesRegex(e.InvalidEvidence, 'Unknown result schema root'):
                e.inspect_static_schemas()
        self.assertEqual(len(calls), 2)
        text = captured.getvalue()
        self.assertIn('StaticSDKType', text)
        self.assertIn('summary --schema', text)
        self.assertIn('tests --schema', text)
        self.assertNotIn('DO_NOT_PRINT_RUNTIME_CONTENT', text)

    def test_schema_diagnostic_bound_and_control_character_escaping(self):
        captured = io.StringIO()
        fixture = {'$ref': 'unknown', 'staticDescription': '\n::warning::' + 'x' * 100_000}
        with patch.object(e, 'command', return_value=json.dumps(fixture).encode()), redirect_stdout(captured):
            with self.assertRaises(e.InvalidEvidence):
                e.inspect_static_schemas()
        text = captured.getvalue()
        self.assertLess(len(text.encode()), 64_000)
        self.assertNotIn('\n::warning::', text)
        self.assertIn('truncated', text)

    def test_actual_xcode26_6_static_schemas_are_accepted(self):
        for kind, schema in SDK_SCHEMAS.items():
            self.assertEqual(e.validate_static_schema(kind, schema), schema['schemas']['Summary' if kind == 'summary' else 'Tests'])
        def output(args):
            self.assertEqual(args[:4], ['xcrun', 'xcresulttool', 'get', 'test-results'])
            self.assertEqual(args[5:], ['--schema'])
            return json.dumps(SDK_SCHEMAS[args[4]]).encode()
        captured = io.StringIO()
        with patch.object(e, 'command', side_effect=output), redirect_stdout(captured):
            e.inspect_static_schemas()
        self.assertEqual(captured.getvalue(), '')

    def test_static_contract_rejects_wrong_roots_fields_types_and_refs(self):
        mutations = []
        mutations.append({'type': 'object', 'properties': {}})
        missing_root = copy.deepcopy(SDK_SCHEMAS['summary'])
        del missing_root['schemas']['Summary']
        mutations.append(missing_root)
        for field_change in ('missing', 'wrong_type', 'external_ref', 'cycle', 'escaped_ref', 'dangling_ref', 'unknown_type'):
            schema = copy.deepcopy(SDK_SCHEMAS['summary'])
            root = schema['schemas']['Summary']
            if field_change == 'missing': del root['properties']['passedTests']
            if field_change == 'wrong_type': root['properties']['passedTests'] = {'type': 'string'}
            if field_change == 'external_ref': root['properties']['result'] = {'$ref': 'https://example.invalid/schema.json'}
            if field_change == 'cycle': root['properties']['result'] = {'$ref': '#/schemas/Summary'}
            if field_change == 'escaped_ref': root['properties']['result'] = {'$ref': '#/schemas/Test~1Result'}
            if field_change == 'dangling_ref': root['properties']['result'] = {'$ref': '#/schemas/Missing'}
            if field_change == 'unknown_type': schema['schemas']['NewType'] = {'type': 'object'}
            mutations.append(schema)
        for schema in mutations:
            with self.subTest(schema_keys=list(schema)):
                with self.assertRaises(e.InvalidEvidence):
                    e.validate_static_schema('summary', schema)
        for change in ('identifier', 'node_type', 'children_ref', 'enum'):
            schema = copy.deepcopy(SDK_SCHEMAS['tests'])
            if change == 'identifier': del schema['schemas']['TestNode']['properties']['nodeIdentifier']
            if change == 'node_type': schema['schemas']['TestNode']['properties']['nodeType'] = {'type': 'integer'}
            if change == 'children_ref': schema['schemas']['TestNode']['properties']['children']['items']['$ref'] = '#/schemas/Tests'
            if change == 'enum': schema['schemas']['TestResult']['enum'].append('Maybe Passed')
            with self.assertRaises(e.InvalidEvidence):
                e.validate_static_schema('tests', schema)

    def test_all_exact_image_contracts_select(self):
        self.assertEqual(sum(map(len, e.EXPECTED.values())), 30)
        for index, (test_id, images) in enumerate(e.EXPECTED.items()):
            inventory = []
            for offset, (name, dimensions) in enumerate(images.items()):
                filename = f'all-{index}-{offset}.png'
                (self.root / filename).write_bytes(png(*min(dimensions)))
                inventory.append({'exportedFileName': filename,
                                  'suggestedHumanReadableName': f'{name}_0_00000000-0000-0000-0000-000000000000.png', 'isAssociatedWithFailure': False})
            result = e.select_manifest([{'testIdentifier': test_id, 'attachments': inventory}], test_id, self.root)
            self.assertEqual(set(result), set(images))

    def test_native_screen_and_hosted_dimensions_cannot_cross(self):
        path = self.root / 'dimensions.png'
        portrait = {(1640, 2360)}
        landscape = {(2360, 1640)}
        hosted = {(1024 * scale, 900 * scale) for scale in (1, 2, 3)}
        for dimensions, valid in [((1640, 2360), portrait), ((2360, 1640), landscape),
                                  ((3072, 2700), hosted)]:
            path.write_bytes(png(*dimensions))
            self.assertEqual(e.png_dimensions(path, valid), dimensions)
            for other in (portrait, landscape, hosted):
                if other != valid:
                    with self.assertRaises(e.InvalidEvidence):
                        e.png_dimensions(path, other)
        for dimensions in ((820, 1180), (3280, 4720), (1640, 2361)):
            path.write_bytes(png(*dimensions))
            with self.assertRaises(e.InvalidEvidence):
                e.png_dimensions(path, portrait)

    def test_only_installed_exact_reviewed_device_type_selected(self):
        runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-26-5'
        runtimes = {'runtimes': [{'identifier': runtime, 'version': '26.5', 'isAvailable': True}]}
        selected = {'name': 'private name never used', 'isAvailable': True,
                    'deviceTypeIdentifier': 'com.apple.CoreSimulator.SimDeviceType.iPad-A16',
                    'udid': '00000000-0000-0000-0000-000000000000'}
        unrelated = {**selected, 'name': 'iPad (A16)', 'deviceTypeIdentifier': 'com.apple.CoreSimulator.SimDeviceType.iPad-unknown'}
        calls = []
        def native(args):
            calls.append(args)
            if args == ['xcrun', 'simctl', 'list', 'runtimes', '--json']:
                return json.dumps(runtimes).encode()
            self.assertEqual(args, ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'])
            return json.dumps({'devices': {runtime: [unrelated, selected]}}).encode()
        with patch.object(runner, 'command', side_effect=native):
            self.assertEqual(runner.destination(), (selected['udid'], '26.5'))
        self.assertEqual(len(calls), 2)
        for devices in ([unrelated], [{**selected, 'isAvailable': False}], []):
            with patch.object(runner, 'command', side_effect=[json.dumps(runtimes).encode(), json.dumps({'devices': {runtime: devices}}).encode()]):
                with self.assertRaises(e.InvalidEvidence):
                    runner.destination()

    def test_accessibility_requires_exact_two_passes_without_skips(self):
        summary = dict(passedTests=2, failedTests=0, skippedTests=0, totalTestCount=2, expectedFailures=0, result='Passed')
        cases = [{'nodeType': 'Test Case', 'nodeIdentifier': f'{e.AX_CLASS}/{method}()', 'result': 'Passed'} for method in e.AX]
        tree = {'testNodes': [{'nodeType': 'UI test bundle', 'name': 'MedicationAdherenceAppUITests', 'children': [
            {'nodeType': 'Test Suite', 'name': e.AX_CLASS, 'children': cases}]}]}
        def validate():
            e.validate_results(summary, tree, e.AX_CLASS, list(e.AX), 'MedicationAdherenceAppUITests')
        validate()
        for key, value in [('passedTests', 3), ('skippedTests', 1), ('totalTestCount', 3)]:
            original = summary[key]
            summary[key] = value
            with self.assertRaises(e.InvalidEvidence):
                validate()
            summary[key] = original
        cases.append(cases[0])
        with self.assertRaises(e.InvalidEvidence):
            validate()
        with self.assertRaises(e.InvalidEvidence):
            e.validate_results(summary, tree, e.AX_CLASS, list(e.AX)[:1], 'MedicationAdherenceAppUITests')

    def test_unknown_and_cross_suite_explicit_images_fail_closed(self):
        row = self.manifest[0]['attachments'][0]
        for name in ('MedicationDetailAX-default-portrait-initial-top',
                     'MedicationDetail-resize-0-320-information',
                     'MedicationDetailAX-default-portrait-initial-information'):
            row['suggestedHumanReadableName'] = f'{name}_0_00000000-0000-0000-0000-000000000000.png'
            self.reject()

    def test_runner_validates_three_suites_then_routes_each_export(self):
        manifest = self.root / 'empty-manifest.json'
        manifest.write_text('[]')
        exports, native_calls = [], []
        def command(args):
            if args == ['xcodebuild', '-version']:
                return b'Xcode 26.6\nBuild version 17A1'
            if args[:3] == ['xcrun', 'xcresulttool', 'export']:
                exports.append((args[args.index('--path') + 1], args[args.index('--test-id') + 1]))
            return b'{}'
        def native(args, **kwargs):
            native_calls.append(args)
            return Mock(returncode=0)
        with ExitStack() as stack:
            stack.enter_context(patch.dict(runner.os.environ, {'RUNNER_TEMP': str(self.root), 'GITHUB_OUTPUT': str(self.root / 'outputs')}))
            stack.enter_context(patch.object(runner, 'trusted_event', return_value='a' * 40))
            stack.enter_context(patch.object(runner, 'synthetic_sources'))
            stack.enter_context(patch.object(runner, 'preflight'))
            stack.enter_context(patch.object(runner, 'destination', return_value=('00000000-0000-0000-0000-000000000000', '26.5')))
            stack.enter_context(patch.object(runner, 'command', side_effect=command))
            stack.enter_context(patch.object(runner.subprocess, 'run', side_effect=native))
            validation = stack.enter_context(patch.object(runner, 'validate_results'))
            stack.enter_context(patch.object(runner, 'safe_file', return_value=manifest))
            stack.enter_context(patch.object(runner, 'select_manifest', return_value={}))
            stack.enter_context(redirect_stdout(io.StringIO()))
            # Empty fake exports must never publish, even with all native exits zero.
            with self.assertRaisesRegex(e.InvalidEvidence, 'Unexpected staging contents'):
                runner.run()
        self.assertEqual(len(native_calls), 3)
        self.assertEqual([call.args[2] for call in validation.call_args_list],
                         [e.DETAIL_CLASS, e.WINDOW_CLASS, e.AX_CLASS])
        self.assertEqual({test_id for _, test_id in exports}, set(e.EXPECTED))
        for bundle, test_id in exports:
            self.assertEqual(Path(bundle).name,
                             'accessibility.xcresult' if test_id.startswith(e.AX_CLASS + '/') else 'detail.xcresult')
        self.assertFalse((self.root / 'medcue-visual-evidence').exists())

    def test_selected_failure_flag_is_explicit_boolean_false(self):
        for value in (None, True, 0, 1, 'false', [], {}):
            with self.subTest(value=value):
                manifest = copy.deepcopy(self.manifest)
                manifest[0]['attachments'][0]['isAssociatedWithFailure'] = value
                self.reject(manifest)
        manifest = copy.deepcopy(self.manifest)
        del manifest[0]['attachments'][0]['isAssociatedWithFailure']
        self.reject(manifest)

    def test_opaque_extra_metadata_cannot_influence_selected_files_or_output(self):
        expected = e.select_manifest(self.manifest, self.test_id, self.root)
        for item in self.manifest[0]['attachments']:
            item.update({'PRIVATE_KEY_MUST_NOT_APPEAR': {
                'exportedFileName': '../SECRET.png', 'suggestedHumanReadableName': 'MedicationDetail-SECRET',
                'isAssociatedWithFailure': True, 'evidence_ready': True, 'status': 'Passed',
                'payload': ['SECRET PATIENT', {'more': 'SECRET'}]}, 'timestamp': {'opaque': 'SECRET'}})
        captured = io.StringIO()
        with redirect_stdout(captured):
            selected = e.select_manifest(self.manifest, self.test_id, self.root, diagnose_contract=True)
        self.assertEqual(selected, expected)
        self.assertEqual(captured.getvalue(), '')

    def test_extras_never_replace_missing_or_invalid_consumed_fields(self):
        for field in ('exportedFileName', 'suggestedHumanReadableName', 'isAssociatedWithFailure'):
            for value in (None, [], {}, 17):
                manifest = copy.deepcopy(self.manifest)
                item = manifest[0]['attachments'][0]
                item['replacement'] = {field: item[field]}
                item[field] = value
                self.reject(manifest)
            manifest = copy.deepcopy(self.manifest)
            item = manifest[0]['attachments'][0]
            item['replacement'] = {field: item.pop(field)}
            self.reject(manifest)

    def test_contract_diagnostic_has_fixed_types_only_not_unknown_keys_or_values(self):
        item = self.manifest[0]['attachments'][0]
        item['isAssociatedWithFailure'] = 'PRIVATE FLAG VALUE'
        item['PRIVATE_UNKNOWN_KEY'] = {'patient': 'PRIVATE DATA', 'path': '/SECRET'}
        item['x' * 10000] = ['PRIVATE ARRAY']
        captured = io.StringIO()
        with redirect_stdout(captured):
            with self.assertRaises(e.InvalidEvidence):
                e.select_manifest(self.manifest, self.test_id, self.root, diagnose_contract=True)
        value = captured.getvalue()
        self.assertLess(len(value), 512)
        self.assertIn('isAssociatedWithFailure=string', value)
        self.assertIn('ignored_field_count_capped100=2', value)
        for forbidden in ('PRIVATE', 'SECRET', str(self.root), 'patient', 'xxxx', '00000000'):
            self.assertNotIn(forbidden, value)
        captured = io.StringIO()
        with redirect_stdout(captured): e.attachment_contract_diagnostic(['PRIVATE ARRAY'])
        self.assertEqual(captured.getvalue(), 'ATTACHMENT_CONTRACT record_type=array\n')

    def test_ax_reason_codes_never_forward_message_values(self):
        path = self.root / 'failure.log'
        for phrase, code in e.AX_FAILURE_REASONS.items():
            with self.subTest(code=code):
                path.write_text(f'/PRIVATE/path/MedicationDetailAccessibilityUITests.swift:315: error: '
                                f'failed - {phrase} PRIVATE_PATIENT /SECRET/device UUID=1234 arbitrary suffix\n')
                result = '\n'.join(e.failure_diagnostics(path))
                self.assertIn('AX reason: ' + code, result)
                for forbidden in ('PRIVATE', 'SECRET', '/path', 'UUID', '1234', 'arbitrary suffix'):
                    self.assertNotIn(forbidden, result)

    def test_ax_reasons_require_failed_ax_context_and_exact_known_stage(self):
        path = self.root / 'failure.log'
        for text in ('MedicationDetailAccessibilityUITests: Medication tab unavailable',
                     'OtherTests.swift:1: error: Medication tab unavailable',
                     'MedicationDetailAccessibilityUITests.swift:315: error: Navigation stage SECRET failed after 15 scrolls',
                     'MedicationDetailAccessibilityUITests.swift:315: error: Navigation stage expand-medication-group-SECRET failed after 15 scrolls'):
            path.write_text(text)
            result = '\n'.join(e.failure_diagnostics(path))
            self.assertNotIn('AX reason:', result)
            self.assertNotIn('SECRET', result)
        path.write_text('MedicationDetailAccessibilityUITests.swift:315: error: '
                        'Navigation stage expand-medication-group failed after SECRET scrolls; expected PRIVATE')
        self.assertIn('AX reason: group_toggle_unavailable', e.failure_diagnostics(path))

    def test_ax_reason_diagnostics_keep_global_output_bounds(self):
        path = self.root / 'failure.log'
        path.write_text('\n'.join(f'MedicationDetailAccessibilityUITests.swift:{offset}: error: failed - {phrase} PRIVATE'
                                  for offset, phrase in enumerate(e.AX_FAILURE_REASONS)))
        result = e.failure_diagnostics(path)
        self.assertLessEqual(len(result), 20)
        self.assertTrue(all(len(line) <= 400 and 'PRIVATE' not in line for line in result))

    def test_duplicate_json_keys_rejected(self):
        with self.assertRaises(e.InvalidEvidence):
            e.decode_json(b'{"passedTests":3,"passedTests":0}')

    def result_fixture(self):
        summary = dict(passedTests=3, failedTests=0, skippedTests=0, totalTestCount=3, expectedFailures=0, result='Passed')
        cases = [{'nodeType': 'Test Case', 'nodeIdentifier': identifier, 'result': 'Passed'} for identifier in e.EXPECTED if identifier.startswith(e.DETAIL_CLASS + '/')]
        tree = {'testNodes': [{'nodeType': 'Test Plan', 'children': [{'nodeType': 'Unit test bundle', 'name': 'MedicationAdherenceAppTests', 'children': [{'nodeType': 'Test Suite', 'name': e.DETAIL_CLASS, 'children': cases}]}]}]}
        return summary, tree, cases

    def validate(self, summary, tree):
        e.validate_results(summary, tree, e.DETAIL_CLASS, list(e.DETAIL), 'MedicationAdherenceAppTests')

    def test_exact_passing_results(self):
        summary, tree, _ = self.result_fixture()
        self.validate(summary, tree)

    def test_skips_failures_bool_counts_missing_duplicate_wrong_id(self):
        for key, value in [('skippedTests', 1), ('failedTests', 1), ('expectedFailures', 1), ('passedTests', True), ('totalTestCount', 2), ('result', 'Failed')]:
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
        captured = io.StringIO()
        with patch.object(e, 'command', side_effect=output), redirect_stdout(captured):
            with self.assertRaises(e.InvalidEvidence):
                e.preflight()
        self.assertEqual(captured.getvalue().splitlines(), [
            'STATIC xcresulttool summary --schema: {"type":"array"}',
            'STATIC xcresulttool tests --schema: {"type":"array"}',
        ])

class PartialRunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name).resolve()
        self.output = self.root / 'outputs'
        self.final = self.root / 'medcue-visual-evidence'
        self.exports = []
        self.native_count = 0

    def tearDown(self):
        self.tmp.cleanup()

    def exercise(self, statuses, guard=None):
        suites = {
            'detail': (e.DETAIL_CLASS, list(e.DETAIL), 'MedicationAdherenceAppTests'),
            'window': (e.WINDOW_CLASS, e.WINDOW, 'MedicationAdherenceAppUITests'),
            'accessibility': (e.AX_CLASS, list(e.AX), 'MedicationAdherenceAppUITests'),
        }
        image_bytes = {}
        handles = ('GITHUB_OUTPUT', 'GITHUB_ENV', 'GITHUB_PATH', 'GITHUB_STEP_SUMMARY', 'GITHUB_STATE')
        def native(args, **kwargs):
            self.assertTrue(all(handle not in kwargs['env'] for handle in handles))
            result = statuses[self.native_count]
            self.native_count += 1
            return Mock(returncode=result)
        def command(args):
            if args == ['xcodebuild', '-version']:
                return b'Xcode 26.6\nBuild version 17A1'
            if args[:2] == ['xcrun', 'swiftc']:
                return b''
            if args[:4] == ['xcrun', 'xcresulttool', 'get', 'test-results']:
                label = Path(args[args.index('--path') + 1]).stem
                cls, methods, target = suites[label]
                if args[4] == 'summary':
                    value = dict(passedTests=len(methods), failedTests=0, skippedTests=0,
                                 totalTestCount=len(methods), expectedFailures=0, result='Passed')
                    if guard == 'identity': value['skippedTests'] = 1
                else:
                    cases = [{'nodeType': 'Test Case', 'nodeIdentifier': f'{cls}/{method}()', 'result': 'Passed'} for method in methods]
                    value = {'testNodes': [{'nodeType': 'Unit test bundle' if label == 'detail' else 'UI test bundle',
                        'name': target, 'children': [{'nodeType': 'Test Suite', 'name': cls, 'children': cases}]}]}
                return json.dumps(value).encode()
            if args[:3] == ['xcrun', 'xcresulttool', 'export']:
                test_id = args[args.index('--test-id') + 1]
                self.exports.append(test_id)
                root = Path(args[args.index('--output-path') + 1])
                root.mkdir()
                inventory = []
                for offset, (name, dimensions) in enumerate(e.EXPECTED[test_id].items()):
                    dim = min(dimensions)
                    if dim not in image_bytes: image_bytes[dim] = png(*dim)
                    filename = f'{offset}.png'
                    (root / filename).write_bytes(b'corrupt' if guard == 'png' else image_bytes[dim])
                    inventory.append({'exportedFileName': filename,
                        'suggestedHumanReadableName': f'{name}_0_00000000-0000-0000-0000-000000000000.png', 'isAssociatedWithFailure': False,
                        'opaqueSDKMetadata': {'evidence_ready': True, 'status': 'Passed', 'exportedFileName': '../SECRET', 'patient': 'PRIVATE_DATA'}})
                (root / 'manifest.json').write_text(json.dumps([{'testIdentifier': test_id, 'attachments': inventory}]))
                return b''
            if Path(args[0]).name == 'sanitize':
                Path(args[2]).write_bytes(Path(args[1]).read_bytes())
                return b''
            self.fail('Unexpected tool invocation')
        with ExitStack() as stack:
            stack.enter_context(patch.dict(runner.os.environ, {
                'RUNNER_TEMP': str(self.root), **{handle: str(self.output) for handle in handles}}))
            stack.enter_context(patch.object(runner, 'trusted_event', return_value='a' * 40))
            stack.enter_context(patch.object(runner, 'synthetic_sources'))
            stack.enter_context(patch.object(runner, 'preflight'))
            stack.enter_context(patch.object(runner, 'destination', return_value=('00000000-0000-0000-0000-000000000000', '26.5')))
            stack.enter_context(patch.object(runner, 'command', side_effect=command))
            stack.enter_context(patch.object(runner.subprocess, 'run', side_effect=native))
            stack.enter_context(patch.object(runner, 'public_repo', side_effect=e.InvalidEvidence('Repository must remain public') if guard == 'public' else None))
            stack.enter_context(redirect_stdout(io.StringIO()))
            return runner.run()

    def test_ax_failure_publishes_only_24_validated_hosted_images_and_stays_failed(self):
        self.assertEqual(self.exercise([0, 0, 65]), 65)
        self.assertEqual(len(list(self.final.glob('*.png'))), 24)
        self.assertEqual(len(self.exports), 3)
        self.assertTrue(all(test.startswith(e.DETAIL_CLASS + '/') for test in self.exports))
        report = json.loads((self.final / 'evidence-status.json').read_text())
        self.assertFalse(report['required_all_passed'])
        self.assertEqual(report['native_exit_status'], 65)
        self.assertEqual(report['suites']['accessibility'], {'status': 'failed', 'verified_passed_tests': None, 'verified_skipped_tests': None})
        self.assertEqual(report['suites']['detail']['verified_passed_tests'], 3)
        self.assertTrue((self.final / 'README.txt').read_text().startswith('PARTIAL'))
        self.assertEqual(self.output.read_text(), 'evidence_ready=false\nevidence_ready=true\n')
        self.assertEqual(report['destination_scope'], 'A16_iPad_simulator')
        self.assertEqual(report['ios_runtime'], '26.5')
        self.assertNotIn('00000000-', json.dumps(report))
        for path in self.final.iterdir():
            self.assertNotIn(b'PRIVATE_DATA', path.read_bytes())
            self.assertNotIn(b'SECRET', path.read_bytes())

    def test_window_failure_does_not_run_or_claim_ax(self):
        self.assertEqual(self.exercise([0, 65]), 65)
        self.assertEqual(self.native_count, 2)
        report = json.loads((self.final / 'evidence-status.json').read_text())
        self.assertEqual(report['suites']['accessibility']['status'], 'not_run')
        self.assertIsNone(report['suites']['accessibility']['verified_passed_tests'])
        self.assertEqual(report['published_png_count'], 24)

    def test_detail_failure_publishes_nothing(self):
        self.assertEqual(self.exercise([65]), 65)
        self.assertEqual(self.native_count, 1)
        self.assertFalse(self.final.exists())
        self.assertEqual(self.exports, [])
        self.assertEqual(self.output.read_text(), 'evidence_ready=false\n')

    def test_zero_exit_without_verified_identity_never_publishes(self):
        with self.assertRaises(e.InvalidEvidence): self.exercise([0, 0, 0], guard='identity')
        self.assertEqual(self.native_count, 1)
        self.assertEqual(self.exports, [])
        self.assertFalse(self.final.exists())
        self.assertEqual(self.output.read_text(), 'evidence_ready=false\n')

    def test_partial_png_guard_failure_never_authorizes_upload(self):
        with self.assertRaises(e.InvalidEvidence): self.exercise([0, 0, 65], guard='png')
        self.assertFalse(self.final.exists())
        self.assertEqual(self.output.read_text(), 'evidence_ready=false\n')

    def test_final_public_guard_failure_never_authorizes_upload(self):
        with self.assertRaises(e.InvalidEvidence): self.exercise([0, 0, 65], guard='public')
        self.assertFalse(self.final.exists())
        self.assertEqual(self.output.read_text(), 'evidence_ready=false\n')

    def test_all_passed_requires_all_30_images(self):
        self.assertEqual(self.exercise([0, 0, 0]), 0)
        self.assertEqual(len(list(self.final.glob('*.png'))), 30)
        report = json.loads((self.final / 'evidence-status.json').read_text())
        self.assertTrue(report['required_all_passed'])
        self.assertTrue(all(value['status'] == 'passed' for value in report['suites'].values()))
        self.assertEqual(len(self.exports), 5)
        self.assertEqual(self.output.read_text(), 'evidence_ready=false\nevidence_ready=true\n')

    def test_stale_staging_blocks_before_native_and_resets_marker(self):
        self.output.write_text('evidence_ready=true\n')
        self.final.mkdir()
        with self.assertRaisesRegex(e.InvalidEvidence, 'Stale staging'): self.exercise([0, 0, 0])
        self.assertEqual(self.native_count, 0)
        self.assertEqual(self.output.read_text().splitlines()[-1], 'evidence_ready=false')

    def test_native_metadata_tools_cannot_write_actions_output_handles(self):
        handles = ('GITHUB_OUTPUT', 'GITHUB_ENV', 'GITHUB_PATH', 'GITHUB_STEP_SUMMARY', 'GITHUB_STATE')
        with patch.dict(e.os.environ, {handle: 'forbidden' for handle in handles}):
            with patch.object(e.subprocess, 'run', return_value=Mock(returncode=0, stdout=b'{}')) as native:
                e.command(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--schema'])
        self.assertTrue(all(handle not in native.call_args.kwargs['env'] for handle in handles))

if __name__ == '__main__':
    unittest.main()
