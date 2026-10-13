"""Interactive deployment transport; credentials are requested without echo."""
import getpass
import json
import sys
import warnings

import paramiko

warnings.simplefilter("error", getpass.GetPassWarning)
client = paramiko.SSHClient()
client.load_system_host_keys()
client.set_missing_host_key_policy(paramiko.RejectPolicy())
try:
    password = getpass.getpass("SSH password: ")
    client.connect(sys.argv[1], username=sys.argv[2], password=password,
                   allow_agent=False, look_for_keys=False,
                   timeout=15, auth_timeout=20, banner_timeout=20)
    password = None
    print("SSH_READY", flush=True)
    for line in sys.stdin:
        try:
            request = json.loads(line)
            if request["action"] == "close":
                break
            if request["action"] == "upload":
                with client.open_sftp() as sftp:
                    sftp.put(request["local"], request["remote"])
                result = {"uploaded": request["remote"]}
            elif request["action"] == "write":
                with client.open_sftp() as sftp:
                    with sftp.file(request["remote"], "w") as target:
                        target.write(request["content"])
                    sftp.chmod(request["remote"], int(request.get("mode", 384)))
                result = {"written": request["remote"]}
            elif request["action"] == "run":
                _, stdout, stderr = client.exec_command(request["command"], timeout=900)
                result = {"output": stdout.read().decode("utf-8", "replace"),
                          "error": stderr.read().decode("utf-8", "replace"),
                          "exitCode": stdout.channel.recv_exit_status()}
            else:
                raise ValueError("Unknown action")
            print(json.dumps(result, ensure_ascii=False), flush=True)
        except Exception as error:
            print(json.dumps({"error": type(error).__name__ + ": " + str(error)}), flush=True)
finally:
    client.close()
