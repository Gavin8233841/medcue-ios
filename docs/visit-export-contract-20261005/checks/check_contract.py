#!/usr/bin/env python3
"""Validate synthetic JSON expectations only. Never executes SwiftData or renders PDF.

This deliberately bounded model covers the supplied fixture values, the source's
period membership, logical-dose choice, ID ordering/counts, and proposed content
allocation. It is NOT an implementation of MedCue's data layer or a native test.
"""
import argparse
import copy
import json
from datetime import datetime, timedelta
from pathlib import Path
from uuid import UUID
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
PROFILES = ('main_inclusive_seconds', 'pr150_half_open')
SCORES = {'taken': 500, 'corrected': 500, 'delayed': 420, 'skipped': 380, 'pending': 300}


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def dt(value):
    result = datetime.fromisoformat(value)
    require(result.tzinfo is not None, 'All timestamps must have an explicit offset')
    return result


def same_ids(actual, expected, label):
    require(len(actual) == len(set(actual)), label + ': duplicate actual ID')
    require(len(expected) == len(set(expected)), label + ': duplicate expected ID')
    require(set(actual) == set(expected), label + ': ID set mismatch')


def order_groups(actual, expected, label):
    """Same-name groups intentionally permit either existing query tie order."""
    offset = 0
    for group in expected:
        require(set(actual[offset:offset + len(group)]) == set(group), label + ': order group mismatch')
        offset += len(group)
    require(offset == len(actual), label + ': unexpected/missing rows')


def effective(task):
    return dt(task['recordedAt'] or task['dueAt'])


def validate_fixture(fixture, profile):
    require(fixture['syntheticOnly'] is True, 'Only synthetic input is accepted')
    bounds = fixture['range']
    require(bounds['calendar'] == 'gregorian', 'Fixture calendar must be explicit')
    zone = ZoneInfo(bounds['timeZone'])
    start = dt(bounds['startInclusive'])
    exclusive = dt(bounds['candidateEndExclusive'])
    inclusive = dt(bounds['mainEndInclusive'])
    selected_first = datetime.fromisoformat(bounds['selectedStart']).replace(tzinfo=zone)
    selected_last = datetime.fromisoformat(bounds['selectedEnd']).replace(tzinfo=zone)
    require(start == min(selected_first, selected_last), 'Incorrect start boundary')
    require(exclusive == max(selected_first, selected_last) + timedelta(days=1), 'Incorrect next-day boundary')
    require(inclusive == exclusive - timedelta(seconds=1), 'Incorrect main inclusive boundary')
    end = inclusive if profile == PROFILES[0] else exclusive

    def within(value):
        instant = dt(value)
        return start <= instant and (instant <= end if profile == PROFILES[0] else instant < end)

    medications = fixture['medications']
    by_id = {m['id']: m for m in medications}
    require(len(by_id) == len(medications), 'Medication UUID is unique; do not deduplicate names')
    for medication in medications:
        UUID(medication['id'])
        require(medication['displayName'][:2].isascii(), 'Fixture sorting model only claims numbered synthetic names')
    plans = {p['id']: p for p in fixture['plans']}
    require(len(plans) == len(fixture['plans']), 'Duplicate plan ID')
    for field in ('tasks', 'doseChanges', 'riskCards', 'lifecycleEvents'):
        ids = [v['id'] for v in fixture[field]]
        require(len(ids) == len(set(ids)), f'Duplicate {field} record ID')
        for value in fixture[field]:
            require(value['medicationID'] in by_id, 'Dangling medication reference is outside this contract')
            if value.get('planID'):
                require(value['planID'] in plans, 'Missing fixture plan')
                require(plans[value['planID']]['medicationID'] == value['medicationID'], 'Plan belongs to different medication')
    require(fixture['healthSignals'] == [], 'No HealthKit samples or new permission is in scope')

    # Mirrors ONLY the documented fixture membership contract, including the
    # existing bounded dueAt candidate query; it does not exercise a database.
    loaded_tasks = [t for t in fixture['tasks']
                    if start - timedelta(hours=24) <= dt(t['dueAt']) <= end + timedelta(hours=24)
                    and within(t['recordedAt'] or t['dueAt'])]
    changes = [c for c in fixture['doseChanges'] if within(c['effectiveFrom'])]
    range_risks = [r for r in fixture['riskCards'] if within(r['lastDetectedAt'])]
    loader_ids = {v['medicationID'] for v in loaded_tasks + changes + range_risks}
    query_order = sorted((m for m in medications if m['id'] in loader_ids), key=lambda m: m['displayName'])
    # String collation equivalence is limited to this corpus's ASCII numeric
    # prefixes; ties preserve query order and are NOT UUID-sorted in production.
    logical = {}
    for task in loaded_tasks:
        require(task['doseValue'] == 1, 'Model intentionally supports only supplied exact integral dose fixtures')
        if task['status'] == 'skipped' and '未来提醒已停用' in task['reason']:
            continue
        local_due = dt(task['dueAt']).astimezone(zone)
        key = (task['medicationID'], local_due.strftime('%Y-%m-%dT%H:%M'), task['doseValue'], task['doseUnit'])
        score = SCORES[task['status']] + (40 if task['recordedAt'] else 0) + (10 if task['reason'].strip() else 0)
        preference = (-score, -effective(task).timestamp(), task['id'].upper())
        if key not in logical or preference < logical[key][0]:
            logical[key] = (preference, task)
    report_tasks = sorted((value[1] for value in logical.values()), key=effective)
    # Every loaded fixture task has an in-range effective date; recorded tasks
    # may have next-day dueAt. Retain the historical-task guard explicitly.
    report_tasks = [t for t in report_tasks if
                    (dt(t['dueAt']) <= end if profile == PROFILES[0] else dt(t['dueAt']) < end)
                    or t['recordedAt'] is not None]
    active_risks = [r for r in range_risks if r['archivedAt'] is None and r['resolvedAt'] is None]
    report_ids = {v['medicationID'] for v in report_tasks + changes + active_risks}
    report_medications = [m for m in query_order if m['id'] in report_ids]
    ordered_ids = [m['id'] for m in report_medications]
    task_med_ids = {t['medicationID'] for t in report_tasks}
    text_ids = [m['id'] for m in report_medications if m['id'] in task_med_ids]
    totals = {status: sum(t['status'] == status for t in report_tasks) for status in SCORES}
    completed = totals['taken'] + totals['corrected']
    per_med = {m['id']: {'total': sum(t['medicationID'] == m['id'] for t in report_tasks),
                       'takenOrCorrected': sum(t['medicationID'] == m['id'] and t['status'] in ('taken', 'corrected') for t in report_tasks)}
               for m in report_medications}
    expected = fixture['expected'][profile]
    same_ids(loader_ids, expected['loaderMedicationIDs'], 'Loader medications')
    same_ids(ordered_ids, expected['reportMedicationIDs'], 'Snapshot medications')
    order_groups(ordered_ids, expected['reportOrderGroups'], 'Medication sorting')
    same_ids([t['id'] for t in report_tasks], expected['reportTaskIDs'], 'Logical report tasks')
    require([t['id'] for t in report_tasks] == expected['reportTaskOrderIDs'], 'Effective-date task order mismatch')
    same_ids({c['medicationID'] for c in changes}, expected['reportDoseChangeMedicationIDs'], 'Dose changes')
    same_ids({r['medicationID'] for r in active_risks}, expected['reportActiveRiskMedicationIDs'], 'Active risks')
    same_ids(text_ids, expected['textMedicationRows'], 'Text task rows')
    actual_counts = {
        'loaderTaskCount': len(loaded_tasks), 'snapshotMedicationCount': len(report_ids),
        'pdfMedicationCount': len(report_medications), 'reportTaskCount': len(report_tasks),
        'completedCount': completed, 'completionRate': completed / len(report_tasks) if report_tasks else 0.0,
        'skippedCount': totals['skipped'], 'delayedCount': totals['delayed'],
        'communicationCount': totals['skipped'] + totals['delayed'] + sum(r['requiresProfessionalReview'] for r in active_risks),
        'textSummaryTaskMedicationCount': len(task_med_ids), 'perMedicationTaskCounts': per_med,
    }
    for key, value in actual_counts.items():
        require(value == expected[key], f'{key}: expected {expected[key]}, actual {value}')
    # This is the PROPOSED allocation contract, not observed PDF output.
    allocation = expected['contentAllocation']
    require(allocation['sectionTitle'] == '所选期间涉及药品', 'Incorrect scope label')
    order_groups(ordered_ids[:4], allocation['firstPageOrderGroups'], 'First page allocation')
    order_groups(ordered_ids[4:], allocation['continuationOrderGroups'], 'Continuation allocation')
    flattened = [i for g in allocation['firstPageOrderGroups'] + allocation['continuationOrderGroups'] for i in g]
    same_ids(flattened, ordered_ids, 'Exactly one medication-list row per ID across report')
    require(allocation['overflowCount'] == max(0, len(ordered_ids) - 4), 'Wrong overflow count')
    require(allocation['requiresContinuation'] == (len(ordered_ids) > 4), 'Empty/missing continuation')
    require(allocation['basePageCount'] == 2, 'Existing two pages must be preserved')
    return actual_counts


def mutation_checks(fixtures):
    main = next(f for f in fixtures if f['case'] == '06_medications')
    mutations = [
        ('exclude archived B', lambda f, e: e['reportMedicationIDs'].pop(1)),
        ('merge equal-name IDs', lambda f, e: e['reportMedicationIDs'].pop()),
        ('add active out-of-period C', lambda f, e: e['reportMedicationIDs'].append(next(m['id'] for m in f['medications'] if m['alias'] == 'C'))),
        ('lose overflow rows', lambda f, e: e['contentAllocation'].__setitem__('continuationOrderGroups', [])),
        ('duplicate first row in continuation', lambda f, e: e['contentAllocation']['continuationOrderGroups'].append(e['contentAllocation']['firstPageOrderGroups'][0])),
        ('keep misleading current label', lambda f, e: e['contentAllocation'].__setitem__('sectionTitle', '当前药品')),
        ('count corrected as not taken', lambda f, e: e.__setitem__('completedCount', e['completedCount'] - 1)),
        ('wrong first-page ordering', lambda f, e: e['contentAllocation']['firstPageOrderGroups'].reverse()),
        ('wrong text task count', lambda f, e: e.__setitem__('textSummaryTaskMedicationCount', 0)),
    ]
    for name, mutate in mutations:
        broken = copy.deepcopy(main)
        mutate(broken, broken['expected'][PROFILES[1]])
        try:
            validate_fixture(broken, PROFILES[1])
        except AssertionError:
            print('PASS negative control:', name)
        else:
            raise AssertionError('Failed to reject mutation: ' + name)
    event_only = copy.deepcopy(next(f for f in fixtures if f['case'] == 'event_only_scope'))
    event_only['expected'][PROFILES[1]]['textSummaryTaskMedicationCount'] = 2
    try:
        validate_fixture(event_only, PROFILES[1])
    except AssertionError:
        print('PASS negative control: equate text task count with event-only Snapshot count')
    else:
        raise AssertionError('Failed to reject event-only count unification')
    swapped = copy.deepcopy(main)
    swapped['medications'].reverse()
    validate_fixture(swapped, PROFILES[1])
    print('PASS tie control: either same-name query order remains valid')
    return len(mutations) + 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mutation-checks', action='store_true')
    args = parser.parse_args()
    paths = sorted((ROOT / 'fixtures').glob('*.json'))
    require(len(paths) == 8, 'Expected the reviewed eight-fixture corpus')
    fixtures = [json.loads(path.read_text(encoding='utf-8')) for path in paths]
    for fixture in fixtures:
        for profile in PROFILES:
            counts = validate_fixture(fixture, profile)
            print(f"PASS {fixture['case']} [{profile}]: medications={counts['pdfMedicationCount']} tasks={counts['reportTaskCount']} completed={counts['completedCount']}")
    if args.mutation_checks:
        print('CONTROLS:', mutation_checks(fixtures))
    print(f'RESULT: PASS {len(fixtures)} synthetic fixtures / {len(fixtures) * len(PROFILES)} profiles')
    print('NOT RUN: SwiftData, Swift compiler, Xcode, PDFKit, native rendering, device accessibility')


if __name__ == '__main__':
    main()
