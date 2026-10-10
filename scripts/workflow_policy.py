"""Local, fail-closed evaluator of the repository's workflow selection subset.

Not a GitHub runner or branch-protection implementation. Glob translation supports
only the literal, *, ** patterns currently used; unsupported expressions fail.
"""
import itertools
from pathlib import Path
import re
import yaml

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    return yaml.load((ROOT / '.github/workflows' / name).read_text(), Loader=yaml.BaseLoader)


def matches(path, pattern):
    if any(c in pattern for c in '![]{}()?'):
        raise ValueError(f'Unsupported glob: {pattern}')
    expression = ''
    i = 0
    while i < len(pattern):
        if pattern[i:i + 3] == '**/':
            expression += '(?:.*/)?'
            i += 3
        elif pattern[i:i + 2] == '**':
            expression += '.*'
            i += 2
        elif pattern[i] == '*':
            expression += '[^/]*'
            i += 1
        else:
            expression += re.escape(pattern[i])
            i += 1
    return re.fullmatch(expression, path) is not None


def selection(paths, event='pull_request', skip_hosted=False):
    workflow = load('ci.yml')
    changes = workflow['jobs']['changes']
    filters = yaml.load(next(s['with']['filters'] for s in changes['steps'] if s.get('id') == 'filter'), Loader=yaml.BaseLoader)
    if event != 'pull_request':
        default = next(s for s in changes['steps'] if s.get('id') == 'defaults')
        assert default['if'] == "${{ github.event_name != 'pull_request' }}"
        assert 'all=true' in default['run']
        assert all("steps.defaults.outputs.all == 'true'" in value for value in changes['outputs'].values())
    flags = {key: event != 'pull_request' or any(matches(p, g) for p in paths for g in globs) for key, globs in filters.items()}
    selected, skipped = set(), set()
    for job in workflow['jobs'].values():
        condition = job.get('if', '${{ true }}')[3:-2].strip()
        condition = re.sub(r"needs.changes.outputs.(\w+) == 'true'", lambda m: str(flags[m[1]]), condition)
        condition = condition.replace("vars.SKIP_HOSTED_PLATFORM_BUILDS != 'true'", str(not skip_hosted)).replace('true', 'True')
        terms = condition.split(' && ')
        if any(t not in ('True', 'False') for t in terms):
            raise ValueError(f'Unsupported condition: {condition}')
        enabled = all(t == 'True' for t in terms)
        matrix = job.get('strategy', {}).get('matrix', {})
        if 'include' in matrix:
            rows = matrix['include']
        elif matrix:
            rows = [dict(zip(matrix, row)) for row in itertools.product(*matrix.values())]
        else:
            rows = [{}]
        for row in rows:
            name = job['name']
            for key, value in row.items():
                name = name.replace('${{ matrix.' + key + ' }}', value)
            (selected if enabled else skipped).add(name)
    return selected, skipped


def documentation_selected(paths):
    return any(matches(p, g) for p in paths for g in load('docs.yml')['on']['pull_request']['paths'])


def aggregate(selected, skipped, results):
    """Fail selected failures; cancellations/missing/unexpected skips need rerun."""
    if selected & skipped or set(results) != selected | skipped:
        raise ValueError('Results must cover the exact selected and skipped universe')
    if any(results[j] == 'failure' for j in selected):
        return 'FAIL'
    if any(results[j] != 'success' for j in selected) or any(results[j] != 'skipped' for j in skipped):
        return 'UNRESOLVED'
    return 'PASS'
