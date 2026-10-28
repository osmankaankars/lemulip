#!/usr/bin/env python3
"""Exercise release coordination against a strict, in-memory GitHub API."""
import copy
import io
from contextlib import redirect_stdout
from pathlib import Path
import unittest
from urllib.parse import parse_qs

import publish_preview as p

CURRENT, PREVIOUS, TAG_OBJECT = 'a' * 40, 'b' * 40, 'c' * 40
VERSION, TAG = '0.1.17', 'v0.1.17'
PREFIX = 'repos/' + p.REPOSITORY


class FakeGitHub:
    def __init__(self):
        self.calls = []
        self.main = CURRENT
        self.tag_source = PREVIOUS
        self.tag_exists = True
        self.annotation = None
        self.tagger = {'name': p.PUBLIC_NAME, 'email': p.PUBLIC_EMAIL}
        self.tag_type = 'tag'
        self.target_type = 'commit'
        self.tag_status = 'success'
        self.current_status = 'success'
        self.omit_job = None
        self.compare = {'status': 'ahead', 'ahead_by': 2, 'behind_by': 0,
                        'base_commit': {'sha': PREVIOUS},
                        'merge_base_commit': {'sha': PREVIOUS}}
        self.release = {'id': 700, 'tag_name': TAG, 'target_commitish': PREVIOUS,
                        'draft': False, 'published_at': '2026-10-28T03:16:30Z',
                        'html_url': p.REPO_URL + '/releases/tag/' + TAG,
                        'assets': [dict(id=800+i, name=name, state='uploaded', size=100,
                                        digest='sha256:'+'d'*64)
                                   for i, name in enumerate((
                                       'Lemulip-'+VERSION+'-macOS-universal.dmg',
                                       'Lemulip-'+VERSION+'-macOS-universal.zip',
                                       'Lemulip-'+VERSION+'-Source.zip', 'SHA256SUMS.txt'))]}
        self.fail_endpoint = None
        self.runs = {}

    @property
    def writes(self):
        return [call for call in self.calls if call[0] != 'GET']

    def request(self, method, endpoint, payload=None, missing_ok=False):
        self.calls.append((method, endpoint, copy.deepcopy(payload)))
        if self.fail_endpoint and self.fail_endpoint in endpoint:
            raise p.PreviewError('Unconfirmed API response')
        route, _, query = endpoint.partition('?')
        if method == 'POST':
            if route == PREFIX+'/git/tags':
                self.tag_source = payload['object']
                self.annotation = payload['message']
                self.tagger = payload['tagger']
                return {'sha': TAG_OBJECT}
            if route == PREFIX+'/git/refs':
                self.tag_exists = True
                return {'ref': payload['ref'], 'object': {'type': 'tag', 'sha': TAG_OBJECT}}
            if route == PREFIX+'/actions/workflows/build.yml/dispatches':
                return None
            raise AssertionError('Unexpected write: '+endpoint)
        if method != 'GET':
            raise AssertionError('Unexpected method: '+method)
        if route == PREFIX:
            return {'id': p.REPOSITORY_ID, 'full_name': p.REPOSITORY, 'private': False,
                    'archived': False, 'default_branch': 'main',
                    'owner': {'id': p.OWNER_ID, 'login': p.OWNER}}
        if route == PREFIX+'/git/ref/heads/main':
            return {'ref': 'refs/heads/main', 'object': {'type': 'commit', 'sha': self.main}}
        if route == PREFIX+'/releases/tags/'+TAG:
            return copy.deepcopy(self.release)
        if route == PREFIX+'/git/ref/tags/'+TAG:
            if not self.tag_exists:
                return None
            return {'ref': 'refs/tags/'+TAG, 'object': {'type': self.tag_type, 'sha': TAG_OBJECT}}
        if route == PREFIX+'/git/tags/'+TAG_OBJECT:
            return {'sha': TAG_OBJECT, 'tag': TAG,
                    'object': {'type': self.target_type, 'sha': self.tag_source},
                    'tagger': copy.deepcopy(self.tagger),
                    'message': self.annotation if self.annotation is not None
                        else p.tag_message(TAG, self.tag_source)}
        if route.startswith(PREFIX+'/compare/'):
            return copy.deepcopy(self.compare)
        if route.startswith(PREFIX+'/actions/workflows/') and route.endswith('/runs'):
            params = parse_qs(query)
            sha, branch = params['head_sha'][0], params['branch'][0]
            filename = route.split('/')[-2]
            status = self.current_status if branch == 'main' else self.tag_status
            if branch != 'main' and status is None:
                return {'total_count': 0, 'workflow_runs': []}
            run_id = 101 if branch == 'main' and filename == 'build.yml' else 102 if branch == 'main' else 103
            run = {'id': run_id, 'run_number': 1, 'run_attempt': 1, 'head_sha': sha,
                   'head_branch': branch, 'event': 'push',
                   'path': '.github/workflows/'+filename,
                   'repository': {'id': p.REPOSITORY_ID},
                   'head_repository': {'id': p.REPOSITORY_ID},
                   'status': 'in_progress' if status == 'pending' else 'completed',
                   'conclusion': None if status == 'pending' else status}
            self.runs[run_id] = run
            return {'total_count': 1, 'workflow_runs': [copy.deepcopy(run)]}
        if route.startswith(PREFIX+'/actions/runs/') and route.endswith('/jobs'):
            run_id = int(route.split('/actions/runs/')[1].split('/')[0])
            run = self.runs[run_id]
            names = p.CODEQL_JOBS if run_id == 102 else p.BUILD_JOBS
            if run_id == 103:
                names += ('Publish Tagged Release',)
            jobs = [dict(name=name, run_id=run_id, run_attempt=1, head_sha=run['head_sha'],
                         head_branch=run['head_branch'], status='completed', conclusion='success')
                    for name in names if name != self.omit_job]
            return {'total_count': len(jobs), 'jobs': jobs}
        raise AssertionError('Unexpected read: '+endpoint)


class PreviewPublisherTests(unittest.TestCase):
    def run_publisher(self, api):
        text = io.StringIO()
        with redirect_stdout(text):
            p.PreviewPublisher(api, CURRENT, VERSION).run()
        return text.getvalue()

    def assert_preserved_error(self, api):
        with self.assertRaises(p.PreviewError):
            self.run_publisher(api)
        self.assertEqual([], api.writes)

    def test_published_ancestor_is_a_successful_read_only_noop(self):
        api = FakeGitHub()
        before = copy.deepcopy(api.release)
        try:
            output = self.run_publisher(api)
        except p.PreviewError as error:
            self.fail('An already published ancestor must be preserved without failure: '+str(error))
        self.assertIn('already published', output)
        self.assertIn('version', output.lower())
        self.assertEqual([], api.writes)
        self.assertEqual(before, api.release)
        self.assertEqual(PREVIOUS, api.tag_source)
        self.assertTrue(any('/compare/'+PREVIOUS+'...'+CURRENT in c[1] for c in api.calls))
        self.assertTrue(any('/attempts/1/jobs' in c[1] for c in api.calls))

    def test_unpublished_previous_tag_still_blocks(self):
        api = FakeGitHub(); api.release = None
        self.assert_preserved_error(api)

    def test_draft_previous_release_is_not_silently_skipped(self):
        api = FakeGitHub(); api.release['draft'] = True
        self.assert_preserved_error(api)

    def test_wrong_release_tag_target_or_publication_is_rejected(self):
        for key, value in [('tag_name', 'v0.1.16'), ('target_commitish', 'main'),
                           ('target_commitish', 'e'*40), ('published_at', None),
                           ('id', True), ('html_url', 'https://example.invalid/release')]:
            with self.subTest(field=key, value=value):
                api = FakeGitHub(); api.release[key] = value
                self.assert_preserved_error(api)

    def test_nonancestor_or_unconfirmed_comparison_is_rejected(self):
        for changes in [{'status': 'diverged'}, {'behind_by': 1}, {'ahead_by': 0},
                        {'base_commit': {'sha': CURRENT}},
                        {'merge_base_commit': {'sha': CURRENT}}]:
            with self.subTest(changes=changes):
                api = FakeGitHub(); api.compare.update(changes)
                self.assert_preserved_error(api)

    def test_missing_corrupt_or_duplicate_assets_do_not_count_as_complete(self):
        for change in ('missing', 'empty', 'pending', 'digest', 'duplicate'):
            with self.subTest(change=change):
                api = FakeGitHub()
                if change == 'missing': api.release['assets'].pop()
                if change == 'empty': api.release['assets'][0]['size'] = 0
                if change == 'pending': api.release['assets'][0]['state'] = 'new'
                if change == 'digest': api.release['assets'][0]['digest'] = 'invalid'
                if change == 'duplicate': api.release['assets'].append(api.release['assets'][0])
                self.assert_preserved_error(api)

    def test_previous_tag_identity_and_annotation_are_still_checked(self):
        for change in ('annotation', 'tagger', 'lightweight', 'target'):
            with self.subTest(change=change):
                api = FakeGitHub()
                if change == 'annotation': api.annotation = 'untrusted annotation'
                if change == 'tagger': api.tagger['name'] = 'another tagger'
                if change == 'lightweight': api.tag_type = 'commit'
                if change == 'target': api.target_type = 'tree'
                self.assert_preserved_error(api)

    def test_previous_publication_job_must_have_succeeded(self):
        for status in ('failure', 'pending', None):
            with self.subTest(status=status):
                api = FakeGitHub(); api.tag_status = status
                self.assert_preserved_error(api)
        api = FakeGitHub(); api.omit_job = 'Publish Tagged Release'
        self.assert_preserved_error(api)

    def test_missing_tag_and_api_uncertainty_cannot_publish(self):
        api = FakeGitHub(); api.tag_exists = False
        self.assert_preserved_error(api)
        for endpoint in ('/compare/', '/releases/tags/', '/git/tags/'):
            with self.subTest(endpoint=endpoint):
                api = FakeGitHub(); api.fail_endpoint = endpoint
                self.assert_preserved_error(api)

    def test_current_ci_and_main_guards_remain_required(self):
        api = FakeGitHub(); api.current_status = 'failure'
        self.assert_preserved_error(api)
        api = FakeGitHub(); api.main = PREVIOUS
        self.assert_preserved_error(api)

    def test_matching_current_tag_keeps_normal_resume_path(self):
        api = FakeGitHub(); api.tag_source = CURRENT
        api.release['target_commitish'] = CURRENT
        output = self.run_publisher(api)
        self.assertIn('already passed', output)
        self.assertEqual([], api.writes)

    def test_matching_current_draft_keeps_normal_resume_path(self):
        api = FakeGitHub(); api.tag_source = CURRENT; api.release['target_commitish'] = CURRENT
        api.release['draft'] = True; api.release['published_at'] = None; api.tag_status = None
        self.run_publisher(api)
        self.assertEqual(1, len(api.writes))
        self.assertTrue(api.writes[0][1].endswith('/dispatches'))

    def test_new_version_creates_tag_and_dispatches_once(self):
        api = FakeGitHub(); api.release = None; api.tag_exists = False; api.tag_status = None
        self.run_publisher(api)
        self.assertEqual(['/git/tags', '/git/refs', '/actions/workflows/build.yml/dispatches'],
                         [call[1].removeprefix(PREFIX) for call in api.writes])
        self.assertEqual(CURRENT, api.tag_source)

    def test_pending_current_tag_is_not_dispatched_twice(self):
        api = FakeGitHub(); api.tag_source = CURRENT; api.release = None; api.tag_status = 'pending'
        output = self.run_publisher(api)
        self.assertIn('no duplicate dispatch', output)
        self.assertEqual([], api.writes)

    def test_failed_current_tag_is_not_rerun_automatically(self):
        api = FakeGitHub(); api.tag_source = CURRENT; api.release = None; api.tag_status = 'failure'
        self.assert_preserved_error(api)

    def test_regression_suite_is_wired_into_build(self):
        workflow = (Path(__file__).resolve().parent.parent/'.github/workflows/build.yml').read_text()
        self.assertIn('python3 script/test_publish_preview.py', workflow)


if __name__ == '__main__':
    unittest.main()
