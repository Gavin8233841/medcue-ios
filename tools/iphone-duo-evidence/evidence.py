#!/usr/bin/env python3
"""Fail-closed native evidence boundary. Python standard library only."""
import json
import hashlib
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import zlib

LIMIT = 20_000_000
DETAIL_CLASS = 'MedicationDetailAdaptiveLayoutTests'
DETAIL = {
    'testRealDetailRendersAndPreservesStoreAcrossNarrowWideNarrow': ['resize-0-320', 'resize-1-1024', 'resize-2-320'],
    'testRealDetailRendersAndPreservesStoreAcrossAX5AndRestoredTraits': ['AX5-320', 'AX5-1024', 'AX5-restored'],
    'testRealDetailRendersAndPreservesStoreWithRTLTraitsAcrossResize': ['RTL-320', 'RTL-1024'],
}
WINDOW_CLASS = 'AdaptiveWindowStateUITests'
WINDOW = [
    'testEarlyConfirmationSurvivesWindowChangesAndCancelThenCommitKeepsOneTask',
    'testFailedSaveAndNextTaskSelectionSurviveWindowChanges',
    'testFailedSaveAcrossWindowChangeLeavesNoDurableLog',
]
EXPECTED = {f'{DETAIL_CLASS}/{method}()': {
    f'MedicationDetail-{state}-{part}': frozenset(((320 if state.endswith('320') else 1024) * scale, 900 * scale) for scale in (1, 2, 3))
    for state in states for part in ['top', 'middle', 'bottom']
} for method, states in DETAIL.items()}

AX_CLASS = 'MedicationDetailAccessibilityUITests'
AX = {
    'testRealDetailContentAndControlsAtDefaultTextSize': 'default',
    'testRealDetailContentAndControlsAtMaximumTextSize': 'AX5',
}
# Native A16 screenshot pixels (UIKit uses @2, never multiply these dimensions).
# Apple: https://support.apple.com/en-us/122240
SCREEN_PIXELS = {'portrait-initial': (1640, 2360), 'landscape': (2360, 1640),
                 'portrait-restored': (1640, 2360)}
EXPECTED.update({f'{AX_CLASS}/{method}()': {
    f'MedicationDetailAX-{size}-{orientation}-top': frozenset({pixels})
    for orientation, pixels in SCREEN_PIXELS.items()
} for method, size in AX.items()})

TEST_CONTRACTS = {
    (DETAIL_CLASS, tuple(DETAIL), 'MedicationAdherenceAppTests'),
    (WINDOW_CLASS, tuple(WINDOW), 'MedicationAdherenceAppUITests'),
    (AX_CLASS, tuple(AX), 'MedicationAdherenceAppUITests'),
}

class InvalidEvidence(Exception):
    pass


def require(value, message):
    if not value:
        raise InvalidEvidence(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON key')
        result[key] = value
    return result


def decode_json(data):
    require(len(data) <= 2_000_000, 'Oversized result metadata')
    return json.loads(data, object_pairs_hook=unique_object)


def command(args):
    # Native tool diagnostics can contain device identifiers; never echo them.
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    require(result.returncode == 0, 'Native evidence command failed; no export')
    require(len(result.stdout) <= 2_000_000, 'Oversized native metadata')
    return result.stdout


def preflight():
    """Read actual help + schema before trusting the modern result contract.

    No legacy fallback, recursive key search, or best-effort acceptance. These
    schema features are the supported contract, not a claim of local Xcode QA.
    """
    for verb, flags in [(['get', 'test-results', 'summary'], ['--path', '--schema']),
                        (['get', 'test-results', 'tests'], ['--path', '--schema']),
                        (['export', 'attachments'], ['--path', '--output-path', '--test-id'])]:
        help_text = command(['xcrun', 'xcresulttool', 'help', *verb]).decode('utf-8')
        require(all(flag in help_text for flag in flags), 'Unsupported xcresulttool command contract')
    # This helper has no path/result input. Diagnostics can only originate from
    # the SDK's fixed --schema commands, never from a result bundle or manifest.
    inspect_static_schemas()


# Exact structural contracts from the real Xcode26.6 run, not inferred schemas.
# Canonical ASCII/sorted/compact JSON digests; provenance is documented in README.
STATIC_SCHEMA_CONTRACTS = {
    'summary': ('Summary', 'de64f404b2cc7dd43e1adee4db1cf5b6af6b44f8d6fa9073cb6a0f85f318d39f'),
    'tests': ('Tests', 'a1cd1c23c7c356f4afce5c4ae965ccf721bbed7c0c8ef4f648136e38387bb07a'),
}


def validate_static_schema(kind, schema):
    require(kind in STATIC_SCHEMA_CONTRACTS, 'Unknown static schema command')
    require(isinstance(schema, dict) and set(schema) == {'schemas'}, 'Unknown result schema root')
    types = schema['schemas']
    require(isinstance(types, dict) and len(types) <= 16, 'Unknown static schema type map')
    root_name, expected_digest = STATIC_SCHEMA_CONTRACTS[kind]
    root = types.get(root_name)
    require(isinstance(root, dict) and root.get('type') == 'object', 'Unknown named result schema root')
    # Comparing the entire observed contract checks every field, primitive type,
    # required list, enum and reference. There is NO generic resolver: external
    # refs, alias cycles, pointer escapes, new types and missing fields all fail.
    # The observed TestNode.children -> TestNode edge is structural recursion;
    # it is never expanded here. Actual result trees remain bounded to depth12.
    try:
        canonical = json.dumps(schema, ensure_ascii=True, sort_keys=True, separators=(',', ':')).encode('ascii')
    except (ValueError, TypeError, RecursionError):
        raise InvalidEvidence('Invalid static schema graph') from None
    require(len(canonical) <= 60_000, 'Oversized static schema contract')
    require(hashlib.sha256(canonical).hexdigest() == expected_digest, 'Unreviewed static schema contract')
    return root


def inspect_static_schemas():
    schemas = {
        kind: decode_json(command(['xcrun', 'xcresulttool', 'get', 'test-results', kind, '--schema']))
        for kind in ('summary', 'tests')
    }
    try:
        for kind, schema in schemas.items():
            validate_static_schema(kind, schema)
    except InvalidEvidence:
        # ASCII JSON escapes line breaks/control characters. A 60KB combined
        # payload budget keeps all framing comfortably below 64KB. Unknown
        # schema remains a failure: this is observation, not a parser fallback.
        budget = 60_000
        for kind, schema in schemas.items():
            payload = json.dumps(schema, ensure_ascii=True, separators=(',', ':'), sort_keys=True)
            shown = payload[:budget]
            budget -= len(shown)
            print(f'STATIC xcresulttool {kind} --schema: {shown}', flush=True)
            if len(shown) < len(payload):
                print('STATIC schema diagnostic truncated at combined 60KB limit.', flush=True)
        raise


def validate_results(summary, tree, class_name, methods, bundle):
    require((class_name, tuple(methods), bundle) in TEST_CONTRACTS, 'Unreviewed test selection')
    require(isinstance(summary, dict), 'Unknown summary')
    for key, expected in [('passedTests', len(methods)), ('failedTests', 0), ('skippedTests', 0), ('expectedFailures', 0), ('totalTestCount', len(methods))]:
        require(type(summary.get(key)) is int and summary[key] == expected, 'Expected exact allowlisted passes / 0 skipped')
    require(summary.get('result') == 'Passed', 'Run did not pass')
    require(isinstance(tree, dict) and isinstance(tree.get('testNodes'), list), 'Unknown test tree')
    expected = {f'{class_name}/{method}()' for method in methods}
    found = []
    def visit(node, active_bundle=None, active_suite=None, depth=0):
        require(depth <= 12 and isinstance(node, dict), 'Invalid test tree nesting')
        kind = node.get('nodeType')
        require(kind in {'Test Plan', 'Unit test bundle', 'UI test bundle', 'Test Suite', 'Test Case'}, 'Unknown test node type')
        if kind in {'Unit test bundle', 'UI test bundle'}:
            require(active_bundle is None and node.get('name') == bundle, 'Unexpected test bundle')
            active_bundle = bundle
        elif kind == 'Test Suite':
            require(node.get('name') == class_name, 'Unexpected test suite')
            active_suite = class_name
        elif kind == 'Test Case':
            require(active_bundle == bundle and active_suite == class_name, 'Unbound test identity')
            identifier = node.get('nodeIdentifier')
            require(identifier in expected and node.get('result') == 'Passed', 'Unexpected or non-passing test')
            require(not node.get('children'), 'Unexpected repeated/parameterized test')
            found.append(identifier)
        children = node.get('children', [])
        require(isinstance(children, list), 'Unknown children schema')
        for child in children:
            visit(child, active_bundle, active_suite, depth + 1)
    for node in tree['testNodes']:
        visit(node)
    require(len(found) == len(expected) and set(found) == expected, 'Missing or duplicate test execution')


def safe_file(root, name, maximum=LIMIT):
    require(isinstance(name, str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,179}', name), 'Unsafe export filename')
    require(name not in {'.', '..'}, 'Unsafe export filename')
    root = Path(root)
    require(root.is_absolute() and root.resolve() == root and not root.is_symlink(), 'Noncanonical export root')
    path = root / name
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and 0 < info.st_size <= maximum, 'Unsafe exported file')
    require(path.resolve().parent == root, 'Export escaped root')
    return path


def png_dimensions(path, allowed_dimensions):
    data = Path(path).read_bytes()
    require(len(data) <= LIMIT and data[:8] == b'\x89PNG\r\n\x1a\n', 'Not a PNG')
    pos, kinds, dimensions, compressed = 8, [], None, []
    while pos < len(data):
        require(pos + 12 <= len(data), 'Truncated PNG')
        size = struct.unpack('>I', data[pos:pos+4])[0]
        kind = data[pos+4:pos+8]
        require(size <= LIMIT and pos + size + 12 <= len(data), 'Invalid PNG chunk')
        require(re.fullmatch(b'[A-Za-z]{4}', kind) and 65 <= kind[2] <= 90, 'Invalid PNG chunk type')
        require(kind[0] >= 97 or kind in {b'IHDR', b'IDAT', b'IEND'}, 'Unknown critical PNG chunk')
        if kind == b'IDAT' and b'IDAT' in kinds:
            require(kinds[-1] == b'IDAT', 'Noncontiguous PNG image data')
        payload = data[pos+8:pos+8+size]
        crc = struct.unpack('>I', data[pos+8+size:pos+12+size])[0]
        require(zlib.crc32(kind + payload) & 0xffffffff == crc, 'Invalid PNG checksum')
        require(kind not in {b'acTL', b'fcTL', b'fdAT'}, 'Animated PNG forbidden')
        if kind == b'IHDR':
            require(not kinds and size == 13, 'Invalid PNG header')
            width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', payload)
            require((width, height) in allowed_dimensions, 'Unexpected screenshot dimensions')
            require(depth == 8 and color in (2, 6) and compression == filtering == interlace == 0, 'Unsupported PNG encoding')
            dimensions = (width, height)
        if kind == b'IDAT':
            compressed.append(payload)
        kinds.append(kind)
        pos += size + 12
        if kind == b'IEND':
            require(size == 0 and pos == len(data), 'PNG trailing data')
            break
    require(dimensions and kinds.count(b'IHDR') == 1 and b'IDAT' in kinds and kinds[-1] == b'IEND', 'Incomplete PNG')
    width, height = dimensions
    stride = width * (4 if color == 6 else 3) + 1
    decoder = zlib.decompressobj()
    try:
        pixels = decoder.decompress(b''.join(compressed), stride * height + 1)
    except zlib.error:
        raise InvalidEvidence('Invalid PNG pixels') from None
    require(len(pixels) == stride * height and decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail, 'Invalid PNG pixel size')
    require(all(pixels[y * stride] <= 4 for y in range(height)), 'Invalid PNG pixel filter')
    return dimensions


def select_manifest(manifest, test_id, root):
    require(isinstance(manifest, list) and len(manifest) == 1, 'Unknown attachment manifest')
    row = manifest[0]
    require(isinstance(row, dict) and set(row) <= {'testIdentifier', 'testIdentifierURL', 'attachments'}, 'Unknown manifest row schema')
    require(row.get('testIdentifier') == test_id, 'Attachment belongs to wrong test')
    attachments = row.get('attachments')
    require(isinstance(attachments, list) and len(attachments) <= 100, 'Invalid attachment inventory')
    require(test_id in EXPECTED, 'Unreviewed attachment test')
    expected = EXPECTED[test_id]
    selected, paths = {}, set()
    for item in attachments:
        require(isinstance(item, dict) and set(item) <= {'exportedFileName', 'suggestedHumanReadableName', 'timestamp', 'isAssociatedWithFailure'}, 'Unknown attachment schema')
        require(item.get('isAssociatedWithFailure', False) is False, 'Failure attachment forbidden')
        name = item.get('suggestedHumanReadableName')
        require(isinstance(name, str), 'Missing attachment name')
        # Known xcresult export spelling: explicit attachment name, ordinal, UUID.
        match = re.fullmatch(r'(MedicationDetail(?:AX)?-[A-Za-z0-9-]+)_\d+_[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}\.png', name)
        if not name.startswith(('MedicationDetail-', 'MedicationDetailAX-')):
            continue  # Automatic screenshots and diagnostics are never staged.
        require(match and match[1] in expected, 'Unknown explicit screenshot')
        fixed = match[1]
        require(fixed not in selected, 'Duplicate screenshot name')
        path = safe_file(root, item.get('exportedFileName'))
        require(path not in paths, 'Duplicate payload mapping')
        paths.add(path)
        png_dimensions(path, expected[fixed])
        selected[fixed] = path
    require(set(selected) == set(expected), 'Incomplete screenshot set')
    return selected


def strip_generated_metadata(path):
    """Drop ancillary chunks; this alone is NOT sufficient for final publication."""
    data = Path(path).read_bytes()
    pos, chunks = 8, [data[:8]]
    while pos < len(data):
        size = struct.unpack('>I', data[pos:pos+4])[0]
        end = pos + size + 12
        if data[pos+4:pos+8] in {b'IHDR', b'IDAT', b'IEND'}:
            chunks.append(data[pos:end])
        pos = end
    Path(path).write_bytes(b''.join(chunks))


def prepare_decode_input(source, destination, allowed_dimensions):
    """Exclude all metadata BEFORE ImageIO can parse/decompress it.

    Pixels are bounded/validated first. Only core chunks are forwarded to the
    native decoder; fresh pixel re-encoding is still mandatory before upload.
    """
    png_dimensions(source, allowed_dimensions)
    with Path(destination).open('xb') as output:
        output.write(Path(source).read_bytes())
    strip_generated_metadata(destination)
    png_dimensions(destination, allowed_dimensions)


def failure_diagnostics(log_path):
    """Return bounded, reconstructed technical diagnostics, never raw log lines.

    All output text is from fixed dictionaries or constrained numeric/Boolean
    fields. No labels, exception descriptions, values, paths, device names,
    UUIDs or arbitrary quoted compiler text are forwarded.
    """
    with Path(log_path).open('rb') as file:
        file.seek(0, 2)
        file.seek(max(0, file.tell() - 131072))
        text = file.read(131072).decode('utf-8', errors='replace')
    output = []
    def add(message):
        if message not in output and len(output) < 20:
            output.append(message[:400])
    files = ('MedicationDetailAdaptiveLayoutTests.swift', 'AdaptiveWindowStateUITests.swift',
             'MedicationDetailView.swift', 'BarcodeScannerView.swift',
             'MedicationDetailAccessibilityUITests.swift')
    for line in text.splitlines():
        if 'error:' in line or 'failed' in line.lower():
            for filename in files:
                match = re.search(re.escape(filename) + r':([0-9]{1,6})(?::[0-9]{1,6})?:', line)
                if match:
                    add(f'{filename}:{match[1]}: native failure')
            for kind in ('XCTAssertTrue', 'XCTAssertFalse', 'XCTAssertEqual', 'XCTAssertNotEqual',
                         'XCTAssertGreaterThanOrEqual', 'XCTAssertLessThanOrEqual', 'XCTUnwrap'):
                if re.search(r'\b' + kind + r'\b.*?\bfailed\b', line):
                    add(kind + ' failed (values withheld)')
            for phrase in ('cannot find', 'has no member', 'no such module', 'missing argument',
                           'extra argument', 'ambiguous use', 'unable to resolve', 'failed to build'):
                if phrase in line.lower():
                    add('Compiler category: ' + phrase)
        for reason in ('noForegroundWindowScene', 'listDidNotMount', 'visibleAccessibilityDidNotStabilize'):
            if reason in line:
                add('Hosted harness: ' + reason)
        for class_name, methods in ((DETAIL_CLASS, DETAIL), (WINDOW_CLASS, WINDOW), (AX_CLASS, AX)):
            if class_name in line and 'failed' in line.lower():
                for method in methods:
                    if method in line:
                        add('Failed test: ' + class_name + '/' + method)
    fields = ('polls', 'maxRaw', 'maxVisible', 'previousVisible', 'rawAX', 'visibleAX',
              'sameOrderedLabels', 'sameLabelMultiset', 'sceneAttached', 'sceneActivationState',
              'attachedToTestWindow', 'descendantViews')
    # Numeric/bool reconstruction is safe even if a log line embeds arbitrary text.
    for field in fields:
        matches = re.findall(r'\b' + field + r'=(true|false|none|-?[0-9]{1,6})(?=[,\s\\"\)]|$)', text)
        if matches:
            add(field + '=' + matches[-1])
    if not output:
        add('No allowlisted failure detail found; raw diagnostics remain private.')
    return output
