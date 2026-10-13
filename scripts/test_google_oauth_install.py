"""Credential validation and isolated rollback tests; never contacts the VPS."""

import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, Mock, patch


SCRIPT = Path(__file__).with_name("install-google-oauth.py")
SPEC = importlib.util.spec_from_file_location("google_oauth_install", SCRIPT)
installer = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = installer
SPEC.loader.exec_module(installer)


def client_document():
    # Synthetic, structurally valid fixture; never used to contact a provider.
    client_id = (
        installer.EXPECTED_PROJECT_NUMBER
        + "-"
        + "ab12cd34ef56gh78ij90kl12mn34op56"
        + ".apps.googleusercontent.com"
    )
    client_secret = "GOCSPX-" + "Ab12Cd34Ef56Gh78Ij90Kl12Mn34Op56"
    return {
        "web": {
            "project_id": installer.EXPECTED_PROJECT,
            "client_id": client_id,
            "client_secret": client_secret,
            "redirect_uris": [installer.EXPECTED_REDIRECT],
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
        }
    }


class ClientValidationTest(unittest.TestCase):
    def test_valid_web_client_returns_only_required_environment_keys(self):
        values = installer.validate_client(client_document())
        self.assertEqual(set(values), set(installer.GOOGLE_KEYS))
        self.assertEqual(values["GOOGLE_REDIRECT_URI"], installer.EXPECTED_REDIRECT)

    def test_rejects_wrong_project_type_and_ambiguous_documents(self):
        mutations = [
            {"installed": client_document()["web"]},
            {"type": "service_account", "project_id": installer.EXPECTED_PROJECT},
            {"web": client_document()["web"], "installed": {}},
            {"web": []},
        ]
        wrong_project = client_document()
        wrong_project["web"]["project_id"] = "another-project"
        mutations.append(wrong_project)
        for document in mutations:
            with self.subTest(document_type=type(document).__name__):
                with self.assertRaises(installer.InstallError):
                    installer.validate_client(document)

    def test_requires_exact_registered_dns_callback(self):
        for uri in (
            "https://103.114.201.109/api/v1/auth/google/callback",
            installer.EXPECTED_REDIRECT + "/",
            installer.EXPECTED_REDIRECT + "?extra=1",
            installer.EXPECTED_REDIRECT.replace("https:", "http:"),
            "https://attacker.example/callback",
        ):
            document = client_document()
            document["web"]["redirect_uris"] = [uri]
            with self.subTest(uri=uri), self.assertRaises(installer.InstallError):
                installer.validate_client(document)

    def test_rejects_secret_control_characters_interpolation_and_placeholder(self):
        synthetic_secret = "GOCSPX-" + "Ab12Cd34Ef56Gh78Ij90"
        for value in (
            "", None, 42, "GOCSPX-" + "a" * 32,
            "GOCSPX-example-Ab12Cd34Ef56Gh78Ij90",
            synthetic_secret + "\nAPP_KEY=attack",
            synthetic_secret + "\rOTHER=value",
            synthetic_secret + "\x00",
            "GOCSPX-${APP_KEY}" + "Ab12Cd34Ef56Gh78Ij90",
            synthetic_secret + "'\"#",
        ):
            document = client_document()
            document["web"]["client_secret"] = value
            with self.subTest(value_type=type(value).__name__), self.assertRaises(installer.InstallError) as caught:
                installer.validate_client(document)
            self.assertNotIn(str(value), str(caught.exception)) if value else None

    def test_rejects_malformed_or_different_project_client_id(self):
        for value in (
            "test-client.apps.googleusercontent.com",
            "999999999999-"
            + "ab12cd34ef56gh78ij90kl12mn34op56"
            + ".apps.googleusercontent.com",
            client_document()["web"]["client_id"] + "\nAPP_KEY=attack",
            "203190518975-" + "a" * 32 + ".apps.googleusercontent.com",
        ):
            document = client_document()
            document["web"]["client_id"] = value
            with self.subTest(client_type=type(value).__name__), self.assertRaises(installer.InstallError):
                installer.validate_client(document)

    def test_rejects_changed_authorization_and_token_endpoints(self):
        for key in ("auth_uri", "token_uri"):
            document = client_document()
            document["web"][key] = "https://attacker.example/oauth"
            with self.subTest(key=key), self.assertRaises(installer.InstallError):
                installer.validate_client(document)

    def test_local_file_must_be_outside_project_and_duplicate_keys_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            project = base / "project"
            project.mkdir()
            inside = project / "client.json"
            inside.write_text(json.dumps(client_document()), encoding="utf-8")
            with self.assertRaises(installer.InstallError):
                installer.load_client(inside, project)
            outside = base / "client.json"
            outside.write_text(json.dumps(client_document()), encoding="utf-8")
            self.assertEqual(installer.load_client(outside, project), installer.validate_client(client_document()))
            outside.write_text('{"web":{},"web":{}}', encoding="utf-8")
            with self.assertRaises(installer.InstallError):
                installer.load_client(outside, project)


class EnvironmentTest(unittest.TestCase):
    def setUp(self):
        self.values = installer.validate_client(client_document())

    def test_only_google_assignments_change_all_other_lines_and_app_key_preserved(self):
        original = (
            b'# server settings\r\nAPP_KEY="base64:ExistingKeyMustStay="\r\n'
            b'DB_PASSWORD="private#db-value"\r\nAUTH_EMAIL_ENABLED=false\r\n'
            b'GOOGLE_CLIENT_ID=\r\nexport GOOGLE_CLIENT_SECRET = "old" # note\r\n'
            b'GOOGLE_REDIRECT_URI=\r\n# GOOGLE_CLIENT_SECRET=comment\r\n'
            b'AUTH_CALLBACK_URIS="msufood://auth/callback,https://103.114.201.109/auth/callback"\r\n'
        )
        result = installer.transform_env(original, self.values)
        for line in original.splitlines(keepends=True):
            if not line.startswith((b"GOOGLE_", b"export GOOGLE_")):
                self.assertIn(line, result)
        for key, value in self.values.items():
            self.assertIn(f"{key}={value}\r\n".encode(), result)
        self.assertEqual(installer.transform_env(result, self.values), result)

    def test_missing_google_keys_append_without_changing_existing_bytes(self):
        original = b"APP_KEY=base64:Existing\nDB_PASSWORD=private"
        result = installer.transform_env(original, self.values)
        self.assertTrue(result.startswith(original + b"\n"))
        for key in installer.GOOGLE_KEYS:
            self.assertEqual(result.count(f"{key}=".encode()), 1)

    def test_ambiguous_or_missing_app_key_and_multiline_environment_abort(self):
        cases = (
            b"DB_DATABASE=msu_food\n",
            b"APP_KEY=\n",
            b"APP_KEY=one\nAPP_KEY=two\n",
            b"APP_KEY=one\nGOOGLE_CLIENT_ID=old\nGOOGLE_CLIENT_ID=duplicate\n",
            b'APP_KEY=one\nOTHER="multiline\nGOOGLE_CLIENT_ID=inside-other-value\n"\n',
            b"APP_KEY=one\nOTHER=has\x00null\n",
        )
        for original in cases:
            with self.subTest(size=len(original)), self.assertRaises(installer.InstallError):
                installer.transform_env(original, self.values)

    def test_unexpected_environment_keys_and_injected_values_abort(self):
        for key, value in (
            ("APP_KEY", "replace-app-key"),
            ("GOOGLE_CLIENT_SECRET", self.values["GOOGLE_CLIENT_SECRET"] + "\nAPP_KEY=attack"),
            ("GOOGLE_REDIRECT_URI", "https://attacker.example/callback"),
        ):
            values = copy.deepcopy(self.values)
            values[key] = value
            with self.subTest(key=key), self.assertRaises(installer.InstallError):
                installer.transform_env(b"APP_KEY=unchanged\n", values)


class TransactionTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.persistent = self.base / "application.env"
        self.release = self.base / "release.env"
        self.cache = self.base / "config.php"
        self.persistent_bytes = b"APP_KEY=persistent-key\nDB_PASSWORD=persistent-db-secret\n"
        self.release_bytes = b"APP_KEY=release-key\nDB_PASSWORD=release-db-secret\n"
        self.cache_bytes = b"<?php return ['private-cache-before'];"
        self.persistent.write_bytes(self.persistent_bytes)
        self.release.write_bytes(self.release_bytes)
        self.cache.write_bytes(self.cache_bytes)
        self.values = installer.validate_client(client_document())
        self.reloads = 0
        self.committed = False

    def regenerate(self):
        self.cache.write_bytes(b"new-private-cache")
        self.committed = True

    def reload(self):
        self.reloads += 1

    def capabilities(self):
        return {
            "googleConfigured": self.cache.exists() and self.cache.read_bytes() == b"new-private-cache",
            "emailConfigured": False,
        }

    def install(self, **overrides):
        callbacks = {
            "regenerate_cache": self.regenerate,
            "reload_fpm": self.reload,
            "verify_capabilities": self.capabilities,
            "check_release": lambda: None,
        }
        callbacks.update(overrides)
        return installer.install_transaction(
            self.persistent, self.release, self.cache, self.base / "backup",
            self.values, None, None, **callbacks,
        )

    def assert_originals(self):
        self.assertEqual(self.persistent.read_bytes(), self.persistent_bytes)
        self.assertEqual(self.release.read_bytes(), self.release_bytes)
        self.assertEqual(self.cache.read_bytes(), self.cache_bytes)

    def test_success_keeps_each_environment_key_and_private_recoverable_backups(self):
        self.assertEqual(self.install(), {"googleConfigured": True, "emailConfigured": False})
        self.assertTrue(self.persistent.read_bytes().startswith(self.persistent_bytes))
        self.assertTrue(self.release.read_bytes().startswith(self.release_bytes))
        self.assertEqual((self.base / "backup/environment-0.before").read_bytes(), self.persistent_bytes)
        self.assertEqual((self.base / "backup/environment-1.before").read_bytes(), self.release_bytes)
        self.assertEqual((self.base / "backup/config-cache.before").read_bytes(), self.cache_bytes)
        self.assertEqual(self.reloads, 1)

    def test_failed_cache_generation_restores_both_environments_and_exact_cache(self):
        def fail():
            self.cache.unlink()
            raise RuntimeError("simulated cache error containing no credentials")

        with self.assertRaisesRegex(installer.InstallError, "previous cache were restored"):
            self.install(regenerate_cache=fail)
        self.assert_originals()
        self.assertEqual(self.reloads, 1)

    def test_failed_public_activation_restores_previous_state_and_reloads_again(self):
        def verify():
            return {"googleConfigured": False, "emailConfigured": False}

        with self.assertRaisesRegex(installer.InstallError, "previous cache were restored"):
            self.install(verify_capabilities=verify)
        self.assert_originals()
        self.assertEqual(self.reloads, 2)

    def test_changed_release_aborts_and_restores_files_before_reload(self):
        checks = 0

        def check():
            nonlocal checks
            checks += 1
            if checks == 2:
                raise RuntimeError("release changed")

        with self.assertRaisesRegex(installer.InstallError, "previous cache were restored"):
            self.install(check_release=check)
        self.assert_originals()
        self.assertEqual(self.reloads, 1)

    def test_rollback_removes_new_cache_when_no_cache_existed_before(self):
        self.cache.unlink()

        def verify():
            return {"googleConfigured": False, "emailConfigured": False}

        with self.assertRaisesRegex(installer.InstallError, "previous cache were restored"):
            self.install(verify_capabilities=verify)
        self.assertFalse(self.cache.exists())
        self.assertEqual(self.persistent.read_bytes(), self.persistent_bytes)
        self.assertEqual(self.release.read_bytes(), self.release_bytes)

    def test_rollback_reload_failure_explicitly_requires_administrator_attention(self):
        def fail_reload():
            raise RuntimeError("reload failed")

        with self.assertRaisesRegex(installer.InstallError, "administrator attention"):
            self.install(reload_fpm=fail_reload)
        self.assert_originals()


class RemoteProgramTest(unittest.TestCase):
    def test_embedded_remote_program_compiles_and_never_embeds_client_values(self):
        program = installer.remote_program(installer.REMOTE_SECRETS + "/google-oauth-" + "a" * 32 + ".json")
        compile(program, "<remote-oauth-installer>", "exec")
        for value in installer.validate_client(client_document()).values():
            if value != installer.EXPECTED_REDIRECT:
                self.assertNotIn(value, program)
        self.assertIn("payload.unlink(missing_ok=True)", program)

    def test_rejects_staging_path_injection(self):
        for path in ("/tmp/client.json", installer.REMOTE_SECRETS + "/../../client.json", "'; echo secret"):
            with self.subTest(path=path), self.assertRaises(installer.InstallError):
                installer.remote_program(path)

    def test_secret_is_uploaded_exclusively_through_private_sftp_not_command(self):
        client = MagicMock()
        sftp = client.open_sftp.return_value
        payload_file = Mock()
        sftp.open.return_value.__enter__.return_value = payload_file
        reject_policy = object()
        paramiko = SimpleNamespace(SSHClient=lambda: client, RejectPolicy=lambda: reject_policy)
        values = installer.validate_client(client_document())
        responses = [
            (0, "ready\n", ""),
            (0, '{"googleConfigured":true,"emailConfigured":false}\n', ""),
        ]
        with patch.dict(sys.modules, {"paramiko": paramiko}), patch.object(installer, "execute_remote", side_effect=responses) as execute:
            result = installer.deploy(values, "synthetic-ssh-password")
        self.assertEqual(result, {"googleConfigured": True, "emailConfigured": False})
        client.load_system_host_keys.assert_called_once()
        client.set_missing_host_key_policy.assert_called_once_with(reject_policy)
        connection = client.connect.call_args.kwargs
        self.assertEqual(client.connect.call_args.args, (installer.VPS_HOST,))
        self.assertEqual(connection["username"], "root")
        self.assertFalse(connection["allow_agent"])
        self.assertFalse(connection["look_for_keys"])
        for call in execute.call_args_list:
            program = call.args[1]
            self.assertNotIn(values["GOOGLE_CLIENT_SECRET"], program)
            self.assertNotIn(values["GOOGLE_CLIENT_ID"], program)
            self.assertNotIn("synthetic-ssh-password", program)
        path, mode = sftp.open.call_args.args
        self.assertTrue(path.startswith(installer.REMOTE_SECRETS + "/google-oauth-"))
        self.assertEqual(mode, "wx")
        sftp.chmod.assert_called_once_with(path, 0o600)
        uploaded = json.loads(payload_file.write.call_args.args[0])
        self.assertEqual(installer.validate_client(uploaded), values)
        sftp.remove.assert_called_once_with(path)

    def test_transport_does_not_request_remote_tty(self):
        client = Mock()
        output, errors = Mock(), Mock()
        output.read.return_value = b"safe output"
        errors.read.return_value = b""
        output.channel.recv_exit_status.return_value = 0
        client.exec_command.return_value = (Mock(), output, errors)
        self.assertEqual(installer.execute_remote(client, "print('safe output')"), (0, "safe output", ""))
        self.assertFalse(client.exec_command.call_args.kwargs["get_pty"])


if __name__ == "__main__":
    unittest.main()
