"""Run on the authorized VPS. Adds an isolated MySQL service without replacing databases."""
import json
import os
from pathlib import Path
import secrets
import subprocess

base = Path('/srv/msu-food')
private = base / 'secrets'
private.mkdir(mode=0o700, parents=True, exist_ok=True)
state = private / 'database.json'
if not state.exists():
    values = {'database': 'msu_food', 'username': 'msu_food',
              'password': secrets.token_hex(32), 'rootPassword': secrets.token_hex(32),
              'testDatabase': 'msu_food_test', 'testUsername': 'msu_food_test',
              'testPassword': secrets.token_hex(32)}
    descriptor = os.open(state, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        json.dump(values, stream)
else:
    values = json.loads(state.read_text())
for key, filename in [('rootPassword', 'mysql-root-password'), ('password', 'mysql-app-password')]:
    target = private / filename
    target.write_text(values[key])
    target.chmod(0o600)

existing = subprocess.run(['docker', 'container', 'inspect', 'msu-food-mysql'], capture_output=True)
if existing.returncode:
    subprocess.run([
        'docker', 'run', '-d', '--name', 'msu-food-mysql', '--restart', 'unless-stopped',
        '--memory', '512m', '--cpus', '0.6', '--pids-limit', '256',
        '-p', '127.0.0.1:3307:3306', '--security-opt', 'no-new-privileges:true',
        '-v', str(base / 'mysql-data') + ':/var/lib/mysql',
        '-v', str(private / 'mysql-root-password') + ':/run/secrets/mysql-root:ro',
        '-v', str(private / 'mysql-app-password') + ':/run/secrets/mysql-app:ro',
        '-e', 'MYSQL_ROOT_PASSWORD_FILE=/run/secrets/mysql-root',
        '-e', 'MYSQL_PASSWORD_FILE=/run/secrets/mysql-app',
        '-e', 'MYSQL_DATABASE=' + values['database'],
        '-e', 'MYSQL_USER=' + values['username'],
        '--health-cmd', 'mysqladmin ping --silent --host=127.0.0.1',
        '--health-interval', '10s', '--health-timeout', '5s', '--health-retries', '12',
        'mysql@sha256:24989179f58856db763f418010c1169fecc944e3ec1ea7e921572d83eb070f70',
        '--innodb-buffer-pool-size=96M', '--performance-schema=OFF',
        '--max-connections=30', '--thread-cache-size=8', '--mysqlx=0',
        '--skip-log-bin', '--innodb-redo-log-capacity=64M',
    ], check=True)
print('Dedicated MySQL container prepared; secrets remain on VPS.')
