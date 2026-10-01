#!/usr/bin/env python3
# Copyright (C) 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
# SPDX-License-Identifier: Apache-2.0
"""Install the LingLong boot service without starting robot hardware."""

import argparse
import datetime
import grp
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess


def render_service(sdk_root, username):
    """Resolve the operator account and render the installed unit template."""
    account = pwd.getpwnam(username)
    if account.pw_uid == 0:
        raise ValueError("The operator must be an ordinary user, not root")
    values = {
        "SDK_ROOT": str(sdk_root),
        "USER": username,
        "GROUP": grp.getgrgid(account.pw_gid).gr_name,
        "HOME": account.pw_dir,
    }
    for name, value in values.items():
        if not re.fullmatch(r"[A-Za-z0-9_./-]+", value):
            raise ValueError(f"Unsupported characters in {name}: {value!r}")
    for program in ("run_linglong.sh", "configure_can_linglong.sh", "hmi_tui",
                    "driver_runtime", "control_runtime", "hmi_runtime"):
        if not os.access(sdk_root / "output/staging/bin" / program, os.X_OK):
            raise ValueError(f"Missing program: {program}; build the SDK first")
    template = sdk_root / "output/staging/share/humanoid_linglong/linglong.service.in"
    unit = template.read_text(encoding="utf-8")
    for name, value in values.items():
        unit = unit.replace(f"@{name}@", value)
    return unit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user", default=os.environ.get("SUDO_USER"), help="ordinary operator account")
    root = next((path for path in Path(__file__).resolve().parents
                 if (path / "build/envsetup.sh").is_file()), Path.cwd())
    parser.add_argument("--sdk-root", type=Path, default=root)
    parser.add_argument("--print-unit", action="store_true", help="render only; do not install or enable")
    args = parser.parse_args()
    if not args.user:
        parser.error("--user is required")
    try:
        unit = render_service(args.sdk_root.resolve(), args.user)
    except (OSError, KeyError, ValueError) as error:
        parser.error(str(error))
    if args.print_unit:
        print(unit, end="")
        return
    if os.geteuid() != 0:
        parser.error("Installation requires sudo --user root")
    if subprocess.run(["systemctl", "is-active", "--quiet", "linglong.service"], check=False).returncode == 0:
        parser.error("Stop linglong.service before installing an update")
    destination = Path("/etc/systemd/system/linglong.service")
    if destination.exists():
        stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        shutil.copy2(destination, destination.with_name(f"linglong.service.{stamp}.bak"))
    temporary = destination.with_suffix(".service.new")
    temporary.write_text(unit, encoding="utf-8")
    temporary.chmod(0o644)
    temporary.replace(destination)
    subprocess.run(["systemctl", "daemon-reload"], check=True)
    subprocess.run(["systemctl", "enable", "linglong.service"], check=True)
    print("Installed and enabled linglong.service for the next boot. Hardware has NOT been started.")
    print("Start: sudo --user root systemctl start linglong.service")
    print("Status: systemctl status linglong.service --no-pager")


if __name__ == "__main__":
    main()
