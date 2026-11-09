"""Synthetic, portable D23 fixtures. No archived native binary is executed or copied."""
from __future__ import annotations

import copy
import hashlib
import json
import struct
import uuid
from pathlib import PurePosixPath

FRAME = 'lemulip_d22_wait_for_release'
BINARY = 'build/NativeSamplerCalibration'
DSYM = 'build/NativeSamplerCalibration.dSYM/Contents/Resources/DWARF/NativeSamplerCalibration'
ROOT = '/synthetic/d23/evidence'
EXE = ROOT + '/' + BINARY
COMMANDS = ('identity-before', 'sample', 'observer-groups', 'target-groups')
SOURCES = {
    'NATIVE_SAMPLER_CALIBRATION.md': 'docs/NATIVE_SAMPLER_CALIBRATION.md',
    'NativeSamplerCalibration.c': 'script/native_ui/NativeSamplerCalibration.c',
    'native-sampler-calibration.yml': '.github/workflows/native-sampler-calibration.yml',
    **{name + '.py': 'script/' + name + '.py' for name in (
        'collect_native_trace_capabilities', 'privacy_check',
        'run_native_recorder_startup_observation', 'run_native_sampler_calibration',
        'run_native_system_trace_startup', 'test_collect_native_trace_capabilities',
        'test_run_native_recorder_startup_observation', 'test_run_native_sampler_calibration',
        'test_run_native_system_trace_startup')},
}
BOUNDS = {
    'cutoffAfterParentBeforeSpawnSeconds': 14.0, 'psTotalSeconds': 1.0,
    'reportBytes': 8388608, 'requiredRemainingWindowSeconds': 8.0,
    'sampleNormalSeconds': 3.5, 'sampleTotalSeconds': 4.0,
    'streamBytes': 2097152, 'targetEOFGraceSeconds': 1.0,
    'targetForcedCleanupSeconds': 1.0, 'triggerAfterTargetSpawnSeconds': 3.0,
}
SCOPE_FALSE = ('activationRouteCoverageEstablished', 'ipcRequestChainEstablished',
               'nativeApplicationsLaunched', 'nativeInputExecuted', 'settingsChanged',
               'recorderImageOrStackQualified', 'recordingExecuted', 'releaseReady')


def identity(raw):
    return {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


def encode(obj):
    return (json.dumps(obj, sort_keys=True, indent=2, allow_nan=False) + '\n').encode()


def clock(seconds):
    ns = round(seconds * 1e9)
    return {'monotonicBeforeNS': ns, 'monotonicAfterNS': ns + 10,
            'wallTimeNS': 1700000000000000000 + ns}


def native_clock(seconds):
    ns = round(seconds * 1e9)
    return {'machAbsoluteBefore': ns, 'machAbsoluteAfter': ns + 10,
            'machContinuousBefore': ns, 'machContinuousAfter': ns + 10,
            'systemUptime': seconds, 'wallTimeUnixNS': 1700000000000000000 + ns}


def macho(architecture, image_uuid, source_sha, debug=False):
    """Tiny non-executable fixture encoding only the Mach-O structures under test."""
    base = 0x100000000
    frame = base + (0x4B0 if architecture == 'arm64' else 0x4C0)
    cpu = {'arm64': 0x100000C, 'x86_64': 0x1000007}[architecture]
    uuid_cmd = struct.pack('<II', 0x1B, 24) + uuid.UUID(image_uuid).bytes
    segment = struct.pack('<II16sQQQQIIII', 0x19, 152, b'__TEXT', base,
                          0x1000, 0, 0x1000, 5, 5, 1, 0)
    section = struct.pack('<16s16sQQIIIIIIII', b'__text', b'__TEXT',
                          base + 0x400, 0x500, 0x400, 2, 0, 0,
                          0x80000400, 0, 0, 0)
    strings = b'\0__mh_execute_header\0_' + FRAME.encode() + b'\0_capture_clock\0'
    frame_idx = strings.index(b'_' + FRAME.encode())
    next_idx = strings.index(b'_capture_clock')
    function_end = base + 0x780
    symtab = struct.pack('<IIIIII', 2, 24, 0x900, 5, 0x950, len(strings))
    commands = uuid_cmd + segment + section + symtab
    data = bytearray(0x1000)
    data[:32] = struct.pack('<8I', 0xFEEDFACF, cpu, 0, 10 if debug else 2,
                           3, len(commands), 0, 0)
    data[32:32 + len(commands)] = commands
    entries = (struct.pack('<IBBHQ', 1, 0x0F, 1, 0, base)
               + struct.pack('<IBBHQ', frame_idx, 0x0F, 1, 0, frame)
               + struct.pack('<IBBHQ', frame_idx, 0x24, 1, 0, frame)
               + struct.pack('<IBBHQ', 0, 0x24, 0, 0, function_end - frame)
               + struct.pack('<IBBHQ', next_idx, 0x0E, 1, 0, function_end))
    data[0x900:0x950] = entries
    data[0x950:0x950 + len(strings)] = strings
    data[0xA00:0xA00 + len(source_sha)] = source_sha.encode()
    return bytes(data)


class Fixture:
    """Mutable semantic fixture; bind() repairs hashes, never semantic values."""

    def __init__(self, architecture='arm64'):
        self.architecture = architecture
        self.files = {}
        self.trust = {
            'schema': 1, 'runID': 'synthetic-run',
            'experimentCommit': 'a' * 40, 'experimentTree': 'b' * 40,
            'frozenCandidate': {'commit': 'c' * 40, 'tree': 'd' * 40},
            'dependencyBase': 'e' * 40, 'sources': {},
            'architectures': {architecture: {'artifactID': 'synthetic-artifact',
                'archive': {'bytes': 0, 'sha256': '0' * 64}, 'members': {}}},
        }
        for name, path in SOURCES.items():
            raw = ('Synthetic test source only: ' + path + '\n').encode()
            self.files['sources/' + name] = raw
            blob = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
            self.trust['sources'][name] = {'path': path, **identity(raw), 'gitBlob': blob}
        source_sha = identity(self.files['sources/NativeSamplerCalibration.c'])['sha256']
        image_uuid = ('11111111-1111-4111-8111-111111111111' if architecture == 'arm64'
                      else '22222222-2222-4222-8222-222222222222')
        self.files[BINARY] = macho(architecture, image_uuid, source_sha)
        self.files[DSYM] = macho(architecture, image_uuid, source_sha, debug=True)
        self.files['build/experiment-commit.txt'] = (self.trust['experimentCommit'] + '\n').encode()
        self.files['build/experiment-tree.txt'] = (self.trust['experimentTree'] + '\n').encode()
        frame_address = 0x1000004B0 if architecture == 'arm64' else 0x1000004C0
        self.files['build/helper-symbols.txt'] = (
            f'0000000100000000 T __mh_execute_header\n{frame_address:016x} T _{FRAME}\n').encode()
        self.files['build/helper-uuid.txt'] = f'UUID: {image_uuid} ({architecture}) {EXE}\n'.encode()
        self.files['build/helper-dsym-uuid.txt'] = (
            f'UUID: {image_uuid} ({architecture}) {ROOT}/{DSYM}\n').encode()
        helper = {'path': EXE, 'sha256': identity(self.files[BINARY])['sha256'],
                  'uuid': image_uuid, 'architecture': architecture,
                  'architectures': [architecture],
                  'uuidOutput': self.files['build/helper-uuid.txt'].decode()}
        provenance = {
            'schema': 1, 'diagnostic': 'D22-native-sampler-calibration',
            'experimentCommit': self.trust['experimentCommit'],
            'experimentTree': self.trust['experimentTree'],
            'architecture': architecture, 'sourceSHA256': source_sha,
            'helper': helper, 'expectedFrame': FRAME,
            'frozenCandidate': self.trust['frozenCandidate'],
            'dependencyBase': self.trust['dependencyBase'],
            'translationProbe': {'returnCode': 0, 'errno': 0, 'value': 0},
            'retainedDiagnosticSourcesSHA256': {
                name: row['sha256'] for name, row in self.trust['sources'].items()},
            'diagnosticOnly': True, 'releaseReady': False, 'C12': 'HOLD',
            'recorderInvoked': False, 'nativeInputExecuted': False,
            'settingsChanged': False, 'activationRouteCoverageEstablished': False,
        }
        self.put('build-provenance.json', provenance)
        ready = {
            'schema': 1, 'kind': 'd22-sampler-calibration-ready',
            'pid': 1234, 'ppid': 1200, 'pgid': 1234, 'euid': 501,
            'executablePath': EXE, 'executableSHA256': helper['sha256'],
            'machOUUID': image_uuid, 'architecture': architecture,
            'nonce': '33333333-3333-4333-8333-333333333333',
            'sourceSHA256': source_sha,
            'experimentCommit': self.trust['experimentCommit'],
            'experimentTree': self.trust['experimentTree'], 'expectedFrame': FRAME,
            'bootUUID': '44444444-4444-4444-8444-444444444444',
            'identityValidated': True, 'nativeInputExecuted': False,
            'settingsChanged': False, 'applicationLaunchRequested': False,
            'recordingRequested': False, 'safetyTimeoutSeconds': 15,
            'machTimebaseNumer': 1, 'machTimebaseDenom': 1,
            'translationProbe': {'returnCode': 0, 'errno': 0, 'value': 0},
            'nativeStartClock': native_clock(100.002),
            'readinessClock': native_clock(100.003),
            'expectedFrameEntered': True, 'receivedInputBytes': 0,
        }
        self.put('target-ready.json', ready)
        final = copy.deepcopy(ready)
        del final['expectedFrameEntered']
        final.update(kind='d22-sampler-calibration-complete', reason='stdin-eof',
                     readyReceiptSHA256=identity(self.files['target-ready.json'])['sha256'],
                     readyReceiptBytes=len(self.files['target-ready.json']),
                     cooperativeEOFObserved=True, safetyTimeoutExpired=False,
                     finalIdentityMatches=True, exitCode=0,
                     elapsedSeconds=4.35800001, releaseClock=native_clock(104.35),
                     completionClock=native_clock(104.36))
        self.put('target-completion.json', final)
        target_argv = [EXE, '--ready', ROOT + '/target-ready.json',
            '--completion', ROOT + '/target-completion.json', '--nonce', ready['nonce'],
            '--expected-executable', EXE, '--expected-sha256', helper['sha256'],
            '--expected-uuid', image_uuid, '--expected-architecture', architecture,
            '--source-sha256', source_sha, '--experiment-commit', self.trust['experimentCommit'],
            '--experiment-tree', self.trust['experimentTree']]
        target = self.command('target', target_argv, 1234, 100.0, 104.37)
        del target['clockAtSpawn'], target['clockAtCompletion']
        del target['normalOperationBudgetSeconds'], target['totalBudgetSeconds']
        target.update(clockBeforeSpawn=clock(100.0), clockAfterCleanup=clock(104.37),
            forcedCleanupUsed=False, pidLeaseReleased=True, stdinBytesSent=0,
            stdinClosed=True, stdinEOFClock=clock(104.34),
            stdinEOFDelivered=True, stdinEOFRequested=True)
        target.pop('cleanupFailureReasons')
        self.put('target.json', target)
        before = self.command('identity-before', ['/bin/ps', '-ww', '-p', '1234', '-o',
            'pid=,ppid=,pgid=,uid=,lstart=,stat=,comm=,args='], 1240, 103.1, 103.2)
        self.put('identity-before.json', before)
        self.files['identity-before.stdout.txt'] = (
            '1234 1200 1234 501 Tue Nov 14 22:15:00 2023 S<s ' + EXE + ' ' +
            ' '.join(target_argv) + '\n').encode()
        sample = self.command('sample', ['/usr/bin/sample', '1234', '1', '10', '-mayDie',
            '-file', '/synthetic/d23/work/controlled-sample.txt'], 1241, 103.3, 104.3)
        self.put('sample.json', sample)
        self.files['sample.stderr.txt'] = b'Synthetic sampler stream; no native invocation.\n'
        for name, pid, start, end in [('observer-groups', 1242, 104.31, 104.32),
                                      ('target-groups', 1243, 104.38, 104.39)]:
            self.put(name + '.json', self.command(name,
                ['/bin/ps', '-A', '-o', 'pid=,pgid=,stat='], pid, start, end))
            self.files[name + '.stdout.txt'] = f'1 1 Ss\n{pid} {pid} R\n'.encode()
        offset = 452 if architecture == 'arm64' else 476
        pc = frame_address + 0x2C90000 + offset
        code = 'ARM64' if architecture == 'arm64' else 'X86-64'
        self.files['controlled-sample.txt'] = f'''Analysis of sampling NativeSamplerCalibration (pid 1234) every 10 milliseconds
Process:         NativeSamplerCalibration [1234]
Path:            /Users/USER/*/NativeSamplerCalibration
Load Address:    0x102c90000
Identifier:      NativeSamplerCalibration
Version:         0
Code Type:       {code}
Platform:        macOS
Parent Process:  Python [1200]
Target Type:     live task
Date/Time:       2023-11-14 22:15:03.300 +0000
Launch Time:     2023-11-14 22:15:00.000 +0000
OS Version:      Synthetic fixture only
Report Version:  7
Analysis Tool:   /usr/bin/sample

Call graph:
    7 Thread_999   DispatchQueue_1: com.apple.main-thread (serial)
      7 main  (in NativeSamplerCalibration) + 16  [0x102c90800]
        7 {FRAME}  (in NativeSamplerCalibration) + {offset}  [0x{pc:x}]
          7 poll  (in libsystem_kernel.dylib) + 8  [0x200000008]

Total number in stack (recursive counted multiple, when >=5):

Sort by top of stack, same collapsed (when >= 5):
        poll  (in libsystem_kernel.dylib)        7

Binary Images:
       0x102c90000 - 0x102c90fff +NativeSamplerCalibration (0) <{image_uuid}> /Users/*/NativeSamplerCalibration
       0x200000000 - 0x200000fff libsystem_kernel.dylib (1) <55555555-5555-4555-8555-555555555555> /usr/lib/system/libsystem_kernel.dylib
'''.encode()
        report = {
            'schema': 1, 'diagnostic': 'D22-native-sampler-calibration',
            'C12': 'HOLD', 'architecture': architecture,
            **{key: False for key in SCOPE_FALSE},
            'experimentCommit': self.trust['experimentCommit'],
            'experimentTree': self.trust['experimentTree'],
            'sourceSHA256': source_sha, 'helper': helper,
            'nonce': ready['nonce'], 'bounds': BOUNDS,
            'controlledSamplerCalibrationComplete': False, 'status': 'calibration-incomplete',
            'errors': ['EvidenceError: Reported process path lacks one matching loaded binary-image entry'],
            'helperStarted': True, 'immutableInputsUnchanged': True,
            'manualPreflightPassed': True, 'sampleInvocationCount': 1,
            'observerCleanupComplete': True, 'targetCleanupComplete': True,
            'readyReceiptUnchanged': True, 'pidLeaseAcquired': True,
            'targetPID': 1234, 'targetParentPID': 1200,
            'parentBeforeSpawnMonotonic': 99.9999, 'targetMonotonicStart': 100.0,
            'triggerMonotonic': 103.0, 'cutoffMonotonic': 113.9999,
            'pidLeaseClock': clock(100.001),
            'observerGroupProof': {'clock': clock(104.33), 'members': [],
                'status': 'no-live-owned-group-members-observed'},
            'targetGroupProof': {'clock': clock(104.4), 'members': [],
                'status': 'no-live-owned-group-members-observed'},
            'beforeIdentity': {'pid': 1234, 'ppid': 1200, 'pgid': 1234,
                'uid': 501, 'startTime': 'Tue Nov 14 22:15:00 2023', 'state': 'S<s',
                'commandTextProvesImage': False,
                'advisoryCommandAndArguments': EXE + ' ' + ' '.join(target_argv)},
        }
        self.put('sampler-calibration.json', report)
        self.bind()

    def get(self, name):
        return json.loads(self.files[name])

    def put(self, name, obj):
        self.files[name] = encode(obj)

    def command(self, name, argv, pid, start, end):
        self.files[name + '.stdout.txt'] = b''
        self.files[name + '.stderr.txt'] = b''
        is_sample = name in ('sample', 'target')
        return {'argv': argv, 'pid': pid, 'status': 'completed', 'exitCode': 0,
            'elapsedSeconds': end - start + 0.001,
            'exitObservedAfterSeconds': end - start,
            'clockAtSpawn': clock(start), 'clockAtCompletion': clock(end),
            'normalOperationBudgetSeconds': 3.5 if is_sample else 0.5,
            'totalBudgetSeconds': 4.0 if is_sample else 1.0,
            'maximumCombinedBytes': 2097152 if is_sample else 65536,
            'inheritedStreamsStillOpen': False, 'cleanupFailed': False,
            'cleanupFailureReasons': [], 'signals': [], 'signalErrors': [],
            'streamErrors': [], 'stopReason': None,
            'files': {}, 'observedBytes': 0, 'retainedBytes': 0}

    def bind(self, *, inputs=True, ready=True, binary=False):
        """Repair byte-level bookkeeping after deliberately inconsistent semantic edits."""
        if binary:
            digest = identity(self.files[BINARY])['sha256']
            p = self.get('build-provenance.json')
            p['helper']['sha256'] = digest
            self.put('build-provenance.json', p)
            for name in ('target-ready.json', 'target-completion.json'):
                d = self.get(name)
                d['executableSHA256'] = digest
                self.put(name, d)
            d = self.get('target.json')
            d['argv'][d['argv'].index('--expected-sha256') + 1] = digest
            self.put('target.json', d)
        if ready:
            d = self.get('target-completion.json')
            d['readyReceiptBytes'] = len(self.files['target-ready.json'])
            d['readyReceiptSHA256'] = identity(self.files['target-ready.json'])['sha256']
            self.put('target-completion.json', d)
        for name in (*COMMANDS, 'target'):
            d = self.get(name + '.json')
            d['files'] = {stream: {'name': name + '.' + stream + '.txt',
                **identity(self.files[name + '.' + stream + '.txt'])}
                for stream in ('stdout', 'stderr')}
            d['observedBytes'] = d['retainedBytes'] = sum(
                d['files'][stream]['bytes'] for stream in ('stdout', 'stderr'))
            self.put(name + '.json', d)
        report = self.get('sampler-calibration.json')
        report['commands'] = {name: self.get(name + '.json') for name in COMMANDS}
        report['target'] = self.get('target.json')
        report['helper'] = self.get('build-provenance.json')['helper']
        report['provenance'] = identity(self.files['build-provenance.json'])
        for key, name in [('readyReceipt', 'target-ready.json'),
                          ('completionReceipt', 'target-completion.json'),
                          ('sampleReport', 'controlled-sample.txt')]:
            report[key] = {'name': name, **identity(self.files[name])}
        self.put('sampler-calibration.json', report)
        if inputs:
            inventory = {}
            for name, raw in self.files.items():
                if name.startswith(('build/', 'sources/')):
                    inventory[name] = {'kind': 'file', **identity(raw)}
                    for parent in PurePosixPath(name).parents:
                        if str(parent) not in ('.', 'build', 'sources'):
                            inventory[str(parent)] = {'kind': 'directory'}
            self.put('inputs-before.json', inventory)
            self.put('inputs-after.json', inventory)
            self.put('input-preservation.json', {'schema': 1, 'inputsUnchanged': True,
                'beforeEntries': len(inventory), 'afterEntries': len(inventory)})
        self.rebind_members()

    def rebind_members(self):
        self.trust['architectures'][self.architecture]['members'] = {
            name: identity(raw) for name, raw in self.files.items()}

    def edit(self, name, mutate, **bind_options):
        value = self.get(name)
        mutate(value)
        self.put(name, value)
        self.bind(**bind_options)

    def replace_report(self, old, new):
        old, new = old.encode(), new.encode()
        assert old in self.files['controlled-sample.txt'], old
        self.files['controlled-sample.txt'] = self.files['controlled-sample.txt'].replace(old, new)
        self.bind()
