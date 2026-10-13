"""Prepare MSU Food release permissions and local-only database credentials on VPS."""
import base64
import grp
import json
import os
from pathlib import Path
import pwd
import secrets
import shutil
import subprocess
import sys

base = Path('/srv/msu-food').resolve()
release = Path(sys.argv[1]).resolve()
if not release.is_relative_to(base / 'releases') or not (release / 'artisan').is_file():
    raise SystemExit('Expected an extracted application release under /srv/msu-food/releases.')
db = json.loads((base / 'secrets/database.json').read_text())
sql = (
    f"CREATE DATABASE IF NOT EXISTS `{db['testDatabase']}` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;\n"
    f"CREATE USER IF NOT EXISTS '{db['testUsername']}'@'%' IDENTIFIED BY '{db['testPassword']}';\n"
    f"GRANT ALL ON `{db['testDatabase']}`.* TO '{db['testUsername']}'@'%';\n"
)
subprocess.run(['docker', 'exec', '-i', 'msu-food-mysql', 'sh', '-c',
                'export MYSQL_PWD="$(cat /run/secrets/mysql-root)"; exec mysql -uroot'],
               input=sql.encode(), check=True)
try:
    account = pwd.getpwnam('msufood')
except KeyError:
    subprocess.run(['useradd', '--system', '--user-group', '--no-create-home',
                    '--home-dir', str(base), '--shell', '/usr/sbin/nologin', 'msufood'], check=True)
    account = pwd.getpwnam('msufood')
environment = base / 'application.env'
if not environment.exists():
    values = {
        'APP_NAME': '"MSU Food"', 'APP_ENV': 'production', 'APP_DEBUG': 'false',
        'APP_KEY': 'base64:' + base64.b64encode(secrets.token_bytes(32)).decode(),
        'APP_URL': 'https://103.114.201.109', 'APP_LOCALE': 'th', 'APP_FALLBACK_LOCALE': 'en',
        'LOG_CHANNEL': 'single', 'LOG_LEVEL': 'warning', 'DB_CONNECTION': 'mysql',
        'DB_HOST': '127.0.0.1', 'DB_PORT': '3307', 'DB_DATABASE': db['database'],
        'DB_USERNAME': db['username'], 'DB_PASSWORD': db['password'],
        'SESSION_DRIVER': 'database', 'SESSION_ENCRYPT': 'true', 'SESSION_SECURE_COOKIE': 'true',
        'SESSION_SAME_SITE': 'lax', 'CACHE_STORE': 'database', 'CACHE_PREFIX': 'msu_food_',
        'QUEUE_CONNECTION': 'sync', 'BROADCAST_CONNECTION': 'null',
        'AUTH_EMAIL_ENABLED': 'false', 'MAIL_MAILER': 'smtp', 'MAIL_SCHEME': 'smtps',
        'MAIL_HOST': '', 'MAIL_PORT': '465', 'MAIL_USERNAME': '', 'MAIL_PASSWORD': '',
        'MAIL_FROM_ADDRESS': '', 'MAIL_FROM_NAME': '"MSU Food"',
        'GOOGLE_CLIENT_ID': '', 'GOOGLE_CLIENT_SECRET': '', 'GOOGLE_REDIRECT_URI': '',
        'AUTH_CALLBACK_URIS': '"msufood://auth/callback,http://localhost:5173/auth/callback,https://103.114.201.109/auth/callback"',
        'CORS_ALLOWED_ORIGINS': '"http://localhost:5173,http://127.0.0.1:5173,https://103.114.201.109"',
    }
    descriptor = os.open(environment, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o640)
    with os.fdopen(descriptor, 'w') as stream:
        stream.write(''.join(f'{key}={value}\n' for key, value in values.items()))
os.chown(environment, 0, account.pw_gid)
environment.chmod(0o640)
shutil.copy2(environment, release / '.env')
for directory, dirs, files in os.walk(release):
    target = Path(directory)
    os.chown(target, 0, account.pw_gid)
    target.chmod(0o750)
    for filename in files:
        target_file = target / filename
        os.chown(target_file, 0, account.pw_gid)
        target_file.chmod(0o640)
for writable in [release / 'storage', release / 'bootstrap/cache']:
    for directory, dirs, files in os.walk(writable):
        os.chown(directory, account.pw_uid, account.pw_gid)
        Path(directory).chmod(0o700)
        for filename in files:
            os.chown(Path(directory) / filename, account.pw_uid, account.pw_gid)
            (Path(directory) / filename).chmod(0o600)
print('Application permissions and isolated test database prepared; no credentials printed.')
