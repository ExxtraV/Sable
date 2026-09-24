#!/usr/bin/env python3
import base64, contextlib, io, json, os, runpy, subprocess
from unittest.mock import patch

base = dict(RELEASE_VERSION='0.5.0', RELEASE_BUILD='5', SPARKLE_PUBLIC_KEY=base64.b64encode(bytes(32)).decode(), SPARKLE_PRIVATE_KEY='test-only', GITHUB_REPOSITORY='test/Sable')
def gh(args):
    return json.dumps([[]] if '--paginate' in args else {'private': False}).encode()
def check(env, expected_error=None):
    with patch.dict(os.environ, env, clear=True), patch.object(subprocess, 'check_output', side_effect=gh), contextlib.redirect_stdout(io.StringIO()):
        try: runpy.run_path('scripts/check-release-config.py', run_name='__main__')
        except SystemExit as error:
            assert expected_error and expected_error in str(error), str(error)
        else: assert expected_error is None
check(base)
check(dict(base, DISTRIBUTION_MODE='community'))
check(dict(base, DISTRIBUTION_MODE='notarized'), 'Missing release settings:')
check(dict(base, DISTRIBUTION_MODE='unknown'), 'Unknown distribution mode.')
check(dict(base, SPARKLE_PRIVATE_KEY=''), 'SPARKLE_PRIVATE_KEY')
check(dict(base, RELEASE_BUILD='0'), 'Build must be a positive integer.')
check(dict(base, RELEASE_CHANNEL='stable'))
check(dict(base, RELEASE_CHANNEL='beta', RELEASE_VERSION='0.5.0-beta.3'))
check(dict(base, RELEASE_CHANNEL='beta'), 'Beta version must look like')
check(dict(base, RELEASE_CHANNEL='beta', RELEASE_VERSION='0.5.0-beta.0'), 'Beta version must look like')
check(dict(base, RELEASE_VERSION='0.5.0-beta.3'), 'Version must be major.minor.patch.')
check(dict(base, RELEASE_CHANNEL='nightly'), 'Unknown release channel.')
print('Passed: community needs no Apple credentials; notarized mode requires them; missing keys and invalid builds fail closed; beta versions carry -beta.N and stable ones never do.')
