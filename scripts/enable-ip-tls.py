"""Give IP clients a default TLS certificate while keeping unknown hosts denied."""
from pathlib import Path
import os
import subprocess

site = Path('/etc/nginx/sites-available/default')
original = site.read_text()
before = '''server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    ssl_reject_handshake on;
}'''
after = '''server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    # IP clients omit TLS SNI. Named sites still use their own certificates.
    ssl_certificate /srv/msu-food/letsencrypt/live/msu-food-ip/fullchain.pem;
    ssl_certificate_key /srv/msu-food/letsencrypt/live/msu-food-ip/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    return 444;
}'''
if after not in original:
    if original.count(before) != 1:
        raise SystemExit('Unexpected default TLS configuration; no changes made.')
    backup = Path('/srv/msu-food/backups/nginx-default-before-ip.conf')
    with backup.open('x') as stream:
        stream.write(original)
    backup.chmod(0o600)
    temporary = site.with_name('default.msu-food.tmp')
    temporary.write_text(original.replace(before, after))
    temporary.chmod(0o644)
    os.replace(temporary, site)
    validation = subprocess.run(['nginx', '-t'])
    if validation.returncode:
        site.write_text(original)
        raise SystemExit('Nginx validation failed; original default restored.')
    subprocess.run(['systemctl', 'reload', 'nginx'], check=True)
print('IP TLS configured. Unknown hosts still return 444; named site blocks preserved.')
