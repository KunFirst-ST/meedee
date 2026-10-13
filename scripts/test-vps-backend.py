"""Run Laravel feature tests against the dedicated MySQL test DB, never the live DB."""
import json
import os
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

base = Path('/srv/msu-food').resolve()
release = Path(sys.argv[1]).resolve()
if not release.is_relative_to(base / 'releases'):
    raise SystemExit('Invalid release path.')
if (release / 'bootstrap/cache/config.php').exists():
    raise SystemExit('Refusing tests in a configured production release. Use a fresh test release without config cache.')
db = json.loads((base / 'secrets/database.json').read_text())
if db['testDatabase'] == db['database'] or not db['testDatabase'].endswith('_test'):
    raise SystemExit('Refusing to run destructive database tests against the live database.')
config = ET.parse(release / 'phpunit.xml')
php = config.getroot().find('php')
for entry in list(php):
    if entry.attrib.get('name', '').startswith('DB_'):
        php.remove(entry)
test_config = release / 'phpunit.mysql.xml'
config.write(test_config)
environment = os.environ.copy()
environment.update({
    'APP_ENV': 'testing', 'DB_CONNECTION': 'mysql', 'DB_HOST': '127.0.0.1',
    'DB_PORT': '3307', 'DB_DATABASE': db['testDatabase'], 'DB_USERNAME': db['testUsername'],
    'DB_PASSWORD': db['testPassword'], 'DB_URL': '', 'CACHE_STORE': 'array',
    'SESSION_DRIVER': 'array', 'MAIL_MAILER': 'array',
})
result = subprocess.run(['php', 'vendor/bin/phpunit', '--configuration', str(test_config)],
                         cwd=release, env=environment)
test_config.unlink(missing_ok=True)
raise SystemExit(result.returncode)
