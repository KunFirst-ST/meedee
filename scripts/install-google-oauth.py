"""Install a downloaded Google Web OAuth client without logging its credentials.

The JSON must stay outside the application source tree. Only its validated OAuth
values are transferred over SFTP to the fixed VPS; SSH trusts known_hosts only.
"""

from __future__ import annotations

import argparse
import getpass
import inspect
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys
import tempfile
from typing import Callable
import warnings


VPS_HOST = "103.114.201.109"
EXPECTED_PROJECT = "msu-foodnaja"
EXPECTED_PROJECT_NUMBER = "203190518975"
EXPECTED_REDIRECT = (
    "https://msu-food.103.114.201.109.nip.io/api/v1/auth/google/callback"
)
REMOTE_SECRETS = "/srv/msu-food/secrets"
GOOGLE_KEYS = ("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "GOOGLE_REDIRECT_URI")


class InstallError(Exception):
    """A static diagnostic which never contains credential material."""


def validate_client(document: object) -> dict[str, str]:
    """Accept only the expected project's registered Web application client."""
    if not isinstance(document, dict) or set(document) != {"web"}:
        raise InstallError("Select a downloaded Google Web application client JSON.")
    web = document["web"]
    if not isinstance(web, dict) or web.get("project_id") != EXPECTED_PROJECT:
        raise InstallError("The OAuth client must belong to the expected Google project.")
    client_id = web.get("client_id")
    if not isinstance(client_id, str) or not re.fullmatch(
        re.escape(EXPECTED_PROJECT_NUMBER)
        + r"-[a-z0-9]{20,128}\.apps\.googleusercontent\.com",
        client_id,
    ):
        raise InstallError("The downloaded OAuth client ID is invalid.")
    client_secret = web.get("client_secret")
    if not isinstance(client_secret, str) or not re.fullmatch(
        r"(?:GOCSPX-)?[A-Za-z0-9_-]{20,128}", client_secret
    ):
        raise InstallError("The downloaded OAuth client secret is invalid.")
    secret_body = client_secret.removeprefix("GOCSPX-")
    placeholder = r"(?:test|sample|dummy|placeholder|example|changeme|replace|redacted|fake|your)(?:[-_]|$)"
    client_body = client_id.split("-", 1)[1].split(".", 1)[0]
    if (
        len(set(secret_body)) < 8
        or len(set(client_body)) < 8
        or re.search(placeholder, secret_body, re.IGNORECASE)
        or re.search(placeholder, client_body, re.IGNORECASE)
    ):
        raise InstallError("Use the original downloaded OAuth client, not sample values.")
    redirects = web.get("redirect_uris")
    if (
        not isinstance(redirects, list)
        or not redirects
        or any(not isinstance(uri, str) for uri in redirects)
        or EXPECTED_REDIRECT not in redirects
    ):
        raise InstallError("Register the exact MSU Food HTTPS callback before installation.")
    if "auth_uri" in web and web["auth_uri"] not in {
        "https://accounts.google.com/o/oauth2/auth",
        "https://accounts.google.com/o/oauth2/v2/auth",
    }:
        raise InstallError("The OAuth authorization endpoint is invalid.")
    if "token_uri" in web and web["token_uri"] not in {
        "https://oauth2.googleapis.com/token",
        "https://www.googleapis.com/oauth2/v4/token",
    }:
        raise InstallError("The OAuth token endpoint is invalid.")
    return {
        "GOOGLE_CLIENT_ID": client_id,
        "GOOGLE_CLIENT_SECRET": client_secret,
        "GOOGLE_REDIRECT_URI": EXPECTED_REDIRECT,
    }


def reject_duplicate_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise InstallError("The OAuth JSON contains duplicate keys.")
        result[key] = value
    return result


def load_client(path: Path, project_root: Path) -> dict[str, str]:
    resolved = path.expanduser().resolve(strict=True)
    root = project_root.resolve(strict=True)
    if resolved.is_relative_to(root):
        raise InstallError("Keep the downloaded OAuth JSON outside the application folder.")
    if not resolved.is_file() or resolved.stat().st_size > 65536:
        raise InstallError("Select a valid downloaded OAuth client JSON file.")
    try:
        document = json.loads(
            resolved.read_text(encoding="utf-8-sig"),
            object_pairs_hook=reject_duplicate_keys,
        )
    except (UnicodeError, json.JSONDecodeError):
        raise InstallError("The OAuth client JSON cannot be read.") from None
    return validate_client(document)


def transform_env(original: bytes, values: dict[str, str]) -> bytes:
    """Replace only the three Google assignments; preserve all other bytes."""
    if set(values) != set(GOOGLE_KEYS):
        raise InstallError("Unexpected OAuth environment keys.")
    # Revalidate before writing dotenv, including rejecting newline/interpolation.
    canonical = validate_client(
        {
            "web": {
                "project_id": EXPECTED_PROJECT,
                "client_id": values["GOOGLE_CLIENT_ID"],
                "client_secret": values["GOOGLE_CLIENT_SECRET"],
                "redirect_uris": [values["GOOGLE_REDIRECT_URI"]],
            }
        }
    )
    if canonical != values:
        raise InstallError("Unexpected OAuth callback environment value.")
    try:
        text = original.decode("utf-8")
    except UnicodeError:
        raise InstallError("The application environment is not valid UTF-8.") from None
    if "\x00" in text or text.startswith("\ufeff"):
        raise InstallError("The application environment contains unsupported content.")
    assignment = re.compile(r"^[ \t]*(?:export[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)[ \t]*=(.*)$")
    seen: set[str] = set()
    app_keys = 0
    newline = "\r\n" if "\r\n" in text else "\n"
    result: list[str] = []
    for line in text.splitlines(keepends=True):
        content = line.rstrip("\r\n")
        match = assignment.match(content)
        if match is None:
            if content.strip() and not content.lstrip().startswith("#"):
                raise InstallError("The application environment contains unsupported multiline values.")
            result.append(line)
            continue
        key, value = match.groups()
        # Do not accidentally replace text inside a multiline dotenv value.
        stripped = value.strip()
        if stripped.startswith(("'", '"')):
            quote = stripped[0]
            if not re.fullmatch(r"(['\"])(?:\\.|(?!\1).)*\1(?:[ \t]+#.*)?", stripped):
                raise InstallError("The application environment contains unsupported multiline values.")
        if key == "APP_KEY":
            app_keys += 1
            if stripped in {"", "''", '""', "null", "(null)"}:
                raise InstallError("The application key must already be configured.")
        if key not in GOOGLE_KEYS:
            result.append(line)
            continue
        if key in seen:
            raise InstallError("The application environment contains duplicate OAuth assignments.")
        seen.add(key)
        ending = line[len(content):]
        result.append(f"{key}={values[key]}{ending}")
    if app_keys != 1:
        raise InstallError("The application must contain exactly one existing application key.")
    missing = [key for key in GOOGLE_KEYS if key not in seen]
    if missing:
        if result and not result[-1].endswith(("\n", "\r")):
            result.append(newline)
        result.extend(f"{key}={values[key]}{newline}" for key in missing)
    return "".join(result).encode("utf-8")


def atomic_write(
    path: Path, data: bytes, owner: tuple[int, int] | None, mode: int
) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=".oauth-", dir=path.parent)
    temporary_path = Path(temporary)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            os.chmod(temporary_path, mode)
            if owner is not None:
                os.chown(temporary_path, *owner)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, path)
        if os.name == "posix":
            directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
    finally:
        temporary_path.unlink(missing_ok=True)


def install_transaction(
    persistent: Path,
    release_env: Path,
    cache: Path,
    backup: Path,
    values: dict[str, str],
    env_owner: tuple[int, int] | None,
    cache_owner: tuple[int, int] | None,
    regenerate_cache: Callable[[], None],
    reload_fpm: Callable[[], None],
    verify_capabilities: Callable[[], dict[str, bool]],
    check_release: Callable[[], None],
) -> dict[str, bool]:
    """Commit both environments and cache, or restore every previous file."""
    originals = [(persistent, persistent.read_bytes()), (release_env, release_env.read_bytes())]
    replacements = [(path, transform_env(data, values)) for path, data in originals]
    old_cache = cache.read_bytes() if cache.exists() else None
    old_cache_mode = stat.S_IMODE(cache.stat().st_mode) if old_cache is not None else 0o600
    old_cache_owner = (
        (cache.stat().st_uid, cache.stat().st_gid)
        if old_cache is not None and os.name == "posix"
        else None
    )
    before = verify_capabilities()
    check_release()
    backup.mkdir(mode=0o700, exist_ok=False)
    backup_owner = (0, 0) if env_owner is not None else None
    for index, (_, data) in enumerate(originals):
        atomic_write(backup / f"environment-{index}.before", data, backup_owner, 0o600)
    if old_cache is not None:
        atomic_write(backup / "config-cache.before", old_cache, backup_owner, 0o600)
    changed = False
    try:
        changed = True
        for path, data in replacements:
            atomic_write(path, data, env_owner, 0o640)
        check_release()
        regenerate_cache()
        if not cache.is_file() or cache.is_symlink():
            raise InstallError("Laravel did not create a valid configuration cache.")
        os.chmod(cache, 0o600)
        if cache_owner is not None:
            os.chown(cache, *cache_owner)
        check_release()
        reload_fpm()
        capabilities = verify_capabilities()
        if capabilities.get("googleConfigured") is not True:
            raise InstallError("The public API did not activate Google OAuth.")
        return capabilities
    except BaseException:
        if not changed:
            raise
        rollback_failed = False
        for path, data in originals:
            try:
                atomic_write(path, data, env_owner, 0o640)
            except BaseException:
                rollback_failed = True
        try:
            if old_cache is None:
                cache.unlink(missing_ok=True)
            else:
                atomic_write(cache, old_cache, old_cache_owner, old_cache_mode)
        except BaseException:
            rollback_failed = True
        try:
            reload_fpm()
            if verify_capabilities() != before:
                rollback_failed = True
        except BaseException:
            rollback_failed = True
        if rollback_failed:
            raise InstallError("Installation failed; automatic rollback needs administrator attention.") from None
        raise InstallError("Installation failed; both environments and the previous cache were restored.") from None


REMOTE_PREPARE = r'''
import os, stat, sys
from pathlib import Path
try:
    base = Path('/srv/msu-food')
    folder = base / 'secrets'
    if os.geteuid() != 0 or base.resolve(strict=True) != base:
        raise RuntimeError()
    if not folder.exists():
        folder.mkdir(mode=0o700)
    info = folder.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0:
        raise RuntimeError()
    folder.chmod(0o700)
    print('ready')
except BaseException:
    print('Private OAuth staging is unavailable.', file=sys.stderr)
    sys.exit(1)
'''


REMOTE_INSTALL = r'''
import fcntl, grp, http.client, pwd, ssl, subprocess, time

def run_quiet(command, cwd=None):
    subprocess.run(command, cwd=cwd, stdin=subprocess.DEVNULL,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   timeout=60, check=True)

def capabilities():
    connection = http.client.HTTPSConnection('103.114.201.109', timeout=5,
                                            context=ssl.create_default_context())
    try:
        connection.request('GET', '/api/v1/capabilities', headers={'Accept': 'application/json'})
        response = connection.getresponse()
        body = response.read(65537)
        if response.status != 200 or len(body) > 65536:
            raise InstallError('The public capabilities endpoint is unavailable.')
        data = json.loads(body)['data']
        if type(data.get('googleConfigured')) is not bool or type(data.get('emailConfigured')) is not bool:
            raise InstallError('The public capabilities response is invalid.')
        return {key: data[key] for key in ('googleConfigured', 'emailConfigured')}
    finally:
        connection.close()

def install():
    os.umask(0o077)
    base = Path('/srv/msu-food')
    folder = base / 'secrets'
    payload = Path(PAYLOAD_PATH)
    try:
        if os.geteuid() != 0 or base.resolve(strict=True) != base:
            raise InstallError('The fixed application directory is unavailable.')
        if payload.parent != folder or not re.fullmatch(r'google-oauth-[0-9a-f]{32}\.json', payload.name):
            raise InstallError('The private OAuth staging path is invalid.')
        info = payload.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o600 or info.st_size > 65536:
            raise InstallError('The private OAuth payload permissions are invalid.')
        with payload.open(encoding='utf-8') as stream:
            values = validate_client(json.load(stream, object_pairs_hook=reject_duplicate_keys))
        current = base / 'current'
        release = current.resolve(strict=True)
        if not release.is_relative_to(base / 'releases') or not (release / 'artisan').is_file():
            raise InstallError('The active Laravel release is invalid.')
        persistent = base / 'application.env'
        release_env = release / '.env'
        cache = release / 'bootstrap/cache/config.php'
        for path in (persistent, release_env):
            if path.is_symlink() or not path.is_file() or path.stat().st_uid != 0:
                raise InstallError('An application environment file is invalid.')
        if cache.is_symlink():
            raise InstallError('The Laravel configuration cache is invalid.')
        account = pwd.getpwnam('msufood')
        group = grp.getgrnam('msufood')

        def check_release():
            if current.resolve(strict=True) != release:
                raise InstallError('The active application release changed during installation.')

        def regenerate_cache():
            run_quiet(['/usr/sbin/runuser', '-u', 'msufood', '--', '/usr/bin/php',
                       'artisan', 'config:cache', '--no-interaction'], cwd=release)

        def reload_fpm():
            run_quiet(['/usr/sbin/php-fpm8.3', '-t'])
            run_quiet(['/usr/bin/systemctl', 'reload', 'php8.3-fpm'])
            time.sleep(0.5)

        lock = folder / '.google-oauth.lock'
        descriptor = os.open(lock, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, 'w') as stream:
            fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
            result = install_transaction(
                persistent, release_env, cache,
                folder / ('google-oauth-backup-' + payload.stem.removeprefix('google-oauth-')),
                values, (0, group.gr_gid), (account.pw_uid, group.gr_gid),
                regenerate_cache, reload_fpm, capabilities, check_release,
            )
        print(json.dumps(result, separators=(',', ':')))
    finally:
        payload.unlink(missing_ok=True)

try:
    install()
except InstallError as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
except BaseException:
    print('Google OAuth installation failed; no credentials were printed.', file=sys.stderr)
    sys.exit(1)
'''


def remote_program(payload_path: str) -> str:
    if not re.fullmatch(re.escape(REMOTE_SECRETS) + r"/google-oauth-[0-9a-f]{32}\.json", payload_path):
        raise InstallError("The private OAuth staging path is invalid.")
    shared = [
        InstallError,
        validate_client,
        reject_duplicate_keys,
        transform_env,
        atomic_write,
        install_transaction,
    ]
    imports = (
        "from __future__ import annotations\n"
        "import json, os, re, stat, sys, tempfile\n"
        "from pathlib import Path\n"
        "from typing import Callable\n"
    )
    constants = "".join(
        f"{key} = {value!r}\n"
        for key, value in {
            "EXPECTED_PROJECT": EXPECTED_PROJECT,
            "EXPECTED_PROJECT_NUMBER": EXPECTED_PROJECT_NUMBER,
            "EXPECTED_REDIRECT": EXPECTED_REDIRECT,
            "GOOGLE_KEYS": GOOGLE_KEYS,
            "PAYLOAD_PATH": payload_path,
        }.items()
    )
    return imports + constants + "\n".join(inspect.getsource(item) for item in shared) + REMOTE_INSTALL


def execute_remote(client: object, program: str, timeout: int = 180) -> tuple[int, str, str]:
    # Program contains source and a random staging filename; never OAuth values.
    command = "python3 - <<'MSU_GOOGLE_OAUTH'\n" + program + "\nMSU_GOOGLE_OAUTH\n"
    _, output, errors = client.exec_command(command, timeout=timeout, get_pty=False)
    stdout = output.read(65537).decode("utf-8", "replace")
    stderr = errors.read(65537).decode("utf-8", "replace")
    return output.channel.recv_exit_status(), stdout, stderr


def deploy(values: dict[str, str], password: str) -> dict[str, bool]:
    import paramiko

    payload = {
        "web": {
            "project_id": EXPECTED_PROJECT,
            "client_id": values["GOOGLE_CLIENT_ID"],
            "client_secret": values["GOOGLE_CLIENT_SECRET"],
            "redirect_uris": [values["GOOGLE_REDIRECT_URI"]],
        }
    }
    payload_path = f"{REMOTE_SECRETS}/google-oauth-{secrets.token_hex(16)}.json"
    client = paramiko.SSHClient()
    client.load_system_host_keys()
    client.set_missing_host_key_policy(paramiko.RejectPolicy())
    sftp = None
    try:
        client.connect(
            VPS_HOST, username="root", password=password,
            allow_agent=False, look_for_keys=False,
            timeout=15, auth_timeout=20, banner_timeout=20,
        )
        password = ""
        status, output, _ = execute_remote(client, REMOTE_PREPARE, timeout=30)
        if status != 0 or output.strip() != "ready":
            raise InstallError("Private OAuth staging is unavailable.")
        sftp = client.open_sftp()
        with sftp.open(payload_path, "wx") as stream:
            sftp.chmod(payload_path, 0o600)
            stream.write(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
            stream.flush()
        status, output, error = execute_remote(client, remote_program(payload_path))
        if status != 0:
            if "automatic rollback needs administrator attention" in error:
                raise InstallError("Installation failed; automatic rollback needs administrator attention.")
            if "both environments and the previous cache were restored" in error:
                raise InstallError("Installation failed; both environments and the previous cache were restored.")
            raise InstallError("Google OAuth installation failed; no credentials were printed.")
        try:
            result = json.loads(output)
        except (ValueError, TypeError):
            raise InstallError("The installation result could not be verified.") from None
        if (
            not isinstance(result, dict)
            or set(result) != {"googleConfigured", "emailConfigured"}
            or any(type(value) is not bool for value in result.values())
            or result["googleConfigured"] is not True
        ):
            raise InstallError("The installation result could not be verified.")
        return result
    finally:
        if sftp is not None:
            try:
                sftp.remove(payload_path)
            except (OSError, EOFError):
                pass
            sftp.close()
        client.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client-json", type=Path, required=True, help="Downloaded Google Web client JSON outside the project.")
    parser.add_argument("--check-only", action="store_true", help="Validate the local file without SSH or deployment.")
    arguments = parser.parse_args()
    try:
        values = load_client(arguments.client_json, Path(__file__).resolve().parents[1])
        if arguments.check_only:
            print("Google Web OAuth client validated; no credentials printed.")
            return 0
        with warnings.catch_warnings():
            warnings.simplefilter("error", getpass.GetPassWarning)
            password = getpass.getpass("VPS root SSH password: ")
        if not password:
            raise InstallError("An SSH password is required.")
        result = deploy(values, password)
        password = ""
        print(json.dumps(result, separators=(",", ":")))
        return 0
    except InstallError as error:
        print(str(error), file=sys.stderr)
    except (KeyboardInterrupt, EOFError):
        print("Google OAuth installation canceled.", file=sys.stderr)
    except BaseException:
        print("Google OAuth installation failed; no credentials were printed.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
