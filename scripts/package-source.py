"""Build a source-only ZIP atomically, excluding local credentials and generated files."""
import os
from pathlib import Path
import sys
import zipfile

sys.stdout.reconfigure(encoding='utf-8')
root = Path(__file__).resolve().parent.parent
target = Path(sys.argv[1]).resolve()
if target.is_relative_to(root):
    raise SystemExit('Choose an output path outside the source directory.')
allowed = {'lib', 'assets', 'android', 'ios', 'web', 'scripts', 'test', 'design', 'backend', '.run'}
excluded = {'vendor', 'node_modules', '.git', '.gradle', '.dart_tool', 'build',
            '.idea', 'Pods', '.symlinks', 'ephemeral', '__pycache__'}
temporary = target.with_name(target.name + '.tmp')
count = 0
with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
    for directory, dirs, files in os.walk(root):
        current = Path(directory)
        dirs[:] = [name for name in dirs if name not in excluded and
                   (current != root or name in allowed)]
        for filename in files:
            path = current / filename
            relative = path.relative_to(root)
            if filename.startswith('.env') and relative != Path('backend/.env.example'):
                continue
            if filename in {'local.properties', 'key.properties', '.phpunit.result.cache'}:
                continue
            if path.suffix.lower() in {'.log', '.sqlite', '.jks', '.keystore', '.pyc'}:
                continue
            if any(part in {'storage', 'cache'} for part in relative.parts[:-1]) and filename != '.gitignore':
                continue
            archive.write(path, relative.as_posix())
            count += 1
with zipfile.ZipFile(temporary) as archive:
    damaged = archive.testzip()
    if damaged:
        raise SystemExit('ZIP integrity failed: ' + damaged)
os.replace(temporary, target)
print(f'{count} files, {target.stat().st_size} bytes: {target}')
