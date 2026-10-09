#!/usr/bin/env python3
"""Private scratch stays on the ephemeral runner; only validated staging uploads."""
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from evidence import (DETAIL, DETAIL_CLASS, WINDOW, WINDOW_CLASS, AX, AX_CLASS, EXPECTED, LIMIT,
                      InvalidEvidence, command, decode_json, preflight, require,
                      validate_results, select_manifest, safe_file, png_dimensions, strip_generated_metadata, prepare_decode_input, failure_diagnostics)

REPO = 'Gavin8233841/medcue-ios'
BRANCH = 'codex/161-iphone-duo-adaptation'
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

def public_repo():
    request = urllib.request.Request(f'https://api.github.com/repos/{REPO}', headers={'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = decode_json(response.read(2_000_001))
    require(data.get('full_name') == REPO and data.get('private') is False and data.get('visibility') == 'public', 'Repository must remain public; no paid/private fallback')

def trusted_event():
    event = decode_json(Path(os.environ['GITHUB_EVENT_PATH']).read_bytes())
    pr = event.get('pull_request', {})
    require(os.environ.get('GITHUB_EVENT_NAME') == 'pull_request' and event.get('number') == 162, 'Wrong event/PR')
    require(event.get('repository', {}).get('full_name') == REPO and event['repository'].get('private') is False, 'Wrong repository')
    require(pr.get('head', {}).get('repo', {}).get('full_name') == REPO and pr['head'].get('ref') == BRANCH, 'Wrong source branch')
    sha = pr['head'].get('sha', '')
    require(re.fullmatch('[0-9a-f]{40}', sha), 'Invalid exact revision')
    require(command(['git', 'rev-parse', 'HEAD']).decode().strip() == sha, 'Checkout is not exact PR head')
    public_repo()
    return sha

# Reviewed synthetic source: a test-source change requires re-review and new hashes.
SOURCE_HASHES = {
    'ios-app/MedicationAdherenceApp/MedicationAdherenceAppTests/MedicationDetailAdaptiveLayoutTests.swift': '6ca65ac4c148e461c69a112c7ae8b7718546702b0f6792b8e13373f651eaf8ff',
    'ios-app/MedicationAdherenceApp/MedicationAdherenceAppUITests/AdaptiveWindowStateUITests.swift': '114b4fe068a838395090932a68a563ca24cf4b4a5ae3b4067636564926beb9ed',
    'ios-app/MedicationAdherenceApp/MedicationAdherenceAppUITests/MedicationDetailAccessibilityUITests.swift': '6f7429ed6f1b50e54bbb9263e8c4ad4d21e0f873eafaaa958ee774819ff6e6a6',
}

def synthetic_sources():
    require(len(SOURCE_HASHES) == 3, 'Missing reviewed source fingerprints')
    for relative, digest in SOURCE_HASHES.items():
        file = ROOT / relative
        require(not file.is_symlink() and hashlib.sha256(file.read_bytes()).hexdigest() == digest, 'Synthetic test source changed; review required')

def destination():
    runtimes = decode_json(command(['xcrun', 'simctl', 'list', 'runtimes', '--json']))['runtimes']
    supported = {r['identifier']: r['version'] for r in runtimes
                 if r.get('isAvailable') is True and r.get('identifier', '').startswith('com.apple.CoreSimulator.SimRuntime.iOS-26-')}
    devices = decode_json(command(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))['devices']
    choices = [(runtime, device) for runtime in sorted(supported) for device in devices.get(runtime, [])
               if device.get('isAvailable') is True and device.get('deviceTypeIdentifier') == 'com.apple.CoreSimulator.SimDeviceType.iPad-A16']
    require(bool(choices), 'No already-installed reviewed A16/iOS26 destination; downloads forbidden')
    runtime, device = choices[0]
    require(re.fullmatch('[0-9A-Fa-f-]{36}', device.get('udid', '')), 'Invalid native destination')
    require(re.fullmatch(r'26\.\d+(?:\.\d+)?', supported[runtime]), 'Unexpected runtime version')
    return device['udid'], supported[runtime]


def native_test_command(scratch, bundle, udid, target, class_name, methods):
    args = ['xcodebuild', 'test', '-project', str(ROOT / 'ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj'),
            '-scheme', 'MedicationAdherenceApp', '-configuration', 'Debug',
            '-destination', f'platform=iOS Simulator,id={udid}', '-destination-timeout', '60',
            '-parallel-testing-enabled', 'NO', '-maximum-concurrent-test-simulator-destinations', '1',
            '-derivedDataPath', str(scratch / 'DerivedData'),
            '-clonedSourcePackagesDirPath', str(scratch / 'source-packages'),
            '-disableAutomaticPackageResolution', '-skipPackageUpdates',
            '-resultBundlePath', str(bundle), '-resultBundleVersion', '3',
            'MEDCUE_SIMULATOR_UNIT_TEST_BUILD=YES', 'CODE_SIGNING_ALLOWED=NO']
    args += [f'-only-testing:{target}/{class_name}/{method}' for method in methods]
    return args

def run():
    sha = trusted_event()
    synthetic_sources()
    version = command(['xcodebuild', '-version']).decode().strip()
    require(re.fullmatch(r'Xcode 26\.6\nBuild version [A-Za-z0-9]+', version), 'Requires preinstalled Xcode26.6; no installation fallback')
    preflight()
    udid, runtime = destination()
    with tempfile.TemporaryDirectory(prefix='medcue-native-', dir=os.environ['RUNNER_TEMP']) as scratch:
        scratch = Path(scratch).resolve()
        sanitizer = scratch / 'sanitize'
        command(['xcrun', 'swiftc', str(HERE / 'sanitize.swift'), '-o', str(sanitizer)])
        bundles = []
        for label, class_name, methods, target in [
            ('detail', DETAIL_CLASS, list(DETAIL), 'MedicationAdherenceAppTests'),
            ('window', WINDOW_CLASS, WINDOW, 'MedicationAdherenceAppUITests'),
            ('accessibility', AX_CLASS, list(AX), 'MedicationAdherenceAppUITests')]:
            bundle = scratch / f'{label}.xcresult'
            args = native_test_command(scratch, bundle, udid, target, class_name, methods)
            # Do not print xcodebuild output: automatic diagnostics may identify devices.
            with (scratch / f'{label}.log').open('wb') as log:
                status = subprocess.run(args, stdout=log, stderr=subprocess.STDOUT, timeout=900,
                                        env={**os.environ, 'MEDCUE_DISABLE_LOCAL_LLAMA': '1'}).returncode
            bundles.append((bundle, class_name, methods, target))
            print(f'{label}: xcodebuild exit {status}', flush=True)
            # Return immediately so later tooling cannot mask the original failure.
            if status:
                try:
                    for diagnostic in failure_diagnostics(scratch / f'{label}.log'):
                        print(diagnostic, flush=True)
                except (OSError, ValueError):
                    print('Allowlisted diagnostics unavailable; preserving native failure.', flush=True)
                return status if 0 < status < 256 else 1
        for bundle, class_name, methods, target in bundles:
            summary = decode_json(command(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)]))
            tree = decode_json(command(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(bundle)]))
            validate_results(summary, tree, class_name, methods, target)
        staging = scratch / 'sanitized'
        staging.mkdir(mode=0o700)
        total = 0
        input_total = 0
        export_bundles = {
            f'{class_name}/{method}()': bundle
            for bundle, class_name, methods, _ in bundles for method in methods
        }
        for index, test_id in enumerate(EXPECTED):
            exported = scratch / f'export-{index}'
            # Tool export can include automatic attachments, but only for this exact
            # allowlisted test. None are trusted or uploaded without validation below.
            command(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(export_bundles[test_id]),
                     '--output-path', str(exported), '--test-id', test_id])
            manifest = decode_json(safe_file(exported, 'manifest.json', 2_000_000).read_bytes())
            selected = select_manifest(manifest, test_id, exported)
            for fixed, source in selected.items():
                input_total += source.stat().st_size
                require(input_total <= LIMIT, 'Input screenshots exceed 20MB')
                target = staging / (fixed + '.png')
                decode_input = scratch / (fixed + '-decode.png')
                prepare_decode_input(source, decode_input, EXPECTED[test_id][fixed])
                command([str(sanitizer), str(decode_input), str(target)])
                file = safe_file(staging, target.name)
                png_dimensions(file, EXPECTED[test_id][fixed])
                strip_generated_metadata(file)
                png_dimensions(file, EXPECTED[test_id][fixed])
                total += file.stat().st_size
                require(total <= LIMIT, 'Evidence exceeds 20MB; no upload')
        names = {name + '.png' for values in EXPECTED.values() for name in values}
        require({p.name for p in staging.iterdir()} == names and len(names) == 30, 'Unexpected staging contents')
        note = (f'Source: {REPO}@{sha}\n{version}\niOS Simulator runtime: {runtime}; installed iPad destination.\n'
                'MedicationDetailAdaptiveLayoutTests: 3 passed, 0 failed, 0 skipped.\n'
                'AdaptiveWindowStateUITests: 3 passed, 0 failed, 0 skipped.\n'
                'MedicationDetailAccessibilityUITests: 2 passed, 0 failed, 0 skipped.\n'
                '24 hosted synthetic render samples: 8 states, top/middle/bottom.\n'
                'Hosted checks cover geometry/traversal/store invariants, not accessibility semantics.\n'
                '6 actual-app synthetic top screenshots: default/AX5, portrait/landscape/restored.\n'
                'Actual-app assertions check content/control accessibility across orientation changes.\n'
                'iPad rotation and hosted container evidence only; not Duo hardware/posture certification.\n'
                'Visual review still required. Existing full verification remains mandatory.\n')
        (staging / 'README.txt').write_text(note)
        require(total + len(note.encode()) <= LIMIT, 'Evidence exceeds 20MB')
        public_repo()  # Recheck immediately before publishing only fresh sanitized files.
        final = Path(os.environ['RUNNER_TEMP']).resolve() / 'medcue-visual-evidence'
        require(not final.exists() and not final.is_symlink(), 'Stale staging forbidden')
        staging.rename(final)
        print(f'Exact source {sha}: 3+3+2 passed, zero skips; 30 sanitized PNGs ready. iPad evidence only.')
    return 0

if __name__ == '__main__':
    try:
        sys.exit(run())
    except (InvalidEvidence, KeyError, ValueError, OSError, subprocess.TimeoutExpired) as error:
        # Fixed diagnostic avoids echoing raw xcresult fields, paths or device IDs.
        reason = str(error) if isinstance(error, InvalidEvidence) else type(error).__name__
        print(f'Native evidence stopped safely: {reason}; no upload.', file=sys.stderr)
        sys.exit(1)
