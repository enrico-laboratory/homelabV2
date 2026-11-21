#!/usr/bin/env python3
"""Writes SMART metrics for the node_exporter textfile collector, using the same metric names as
smartctl_exporter so the alert rules and the Grafana dashboard of the monitor-stack work unchanged.

Needs root (smartctl opens the raw disks). On TrueNAS run it from a UI Cron Job as root:
  OUT_DIR=<textfile dir> python3 <path>/smart-metrics.py
"""
import json
import os
import subprocess
import sys
import tempfile
import time

OUT_DIR = os.environ.get("OUT_DIR", "/var/lib/node_exporter")
SMARTCTL = os.environ.get("SMARTCTL", "/usr/sbin/smartctl")


def esc(v):
    return str(v).replace("\\", "\\\\").replace('"', '\\"')


def lbl(**kw):
    return "{" + ",".join(f'{k}="{esc(v)}"' for k, v in kw.items()) + "}"


def render(dev, d):
    """Prometheus lines for one `smartctl --json -a` document."""
    out = []
    out.append("smartctl_device" + lbl(device=dev, model_name=d.get("model_name", "unknown"),
                                        serial_number=d.get("serial_number", "unknown"),
                                        firmware_version=d.get("firmware_version", "")) + " 1")
    passed = d.get("smart_status", {}).get("passed")
    if passed is not None:
        out.append("smartctl_device_smart_status" + lbl(device=dev) + f" {1 if passed else 0}")
    temp = d.get("temperature", {}).get("current")
    if temp is not None:
        out.append("smartctl_device_temperature" + lbl(device=dev, temperature_type="current") + f" {temp}")
    hours = d.get("power_on_time", {}).get("hours")
    if hours is not None:
        out.append("smartctl_device_power_on_seconds" + lbl(device=dev) + f" {hours * 3600}")
    for a in d.get("ata_smart_attributes", {}).get("table", []):
        base = dict(attribute_id=a["id"], attribute_name=a["name"], device=dev)
        for kind, val in (("raw", a.get("raw", {}).get("value")), ("value", a.get("value")),
                          ("worst", a.get("worst")), ("thresh", a.get("thresh"))):
            if val is not None:
                out.append("smartctl_device_attribute" + lbl(attribute_value_type=kind, **base) + f" {val}")
    return out


def smartctl_json(*args):
    # smartctl exits non-zero for many non-fatal reasons (bitmask), so ignore the exit code.
    r = subprocess.run([SMARTCTL, "--json", *args], capture_output=True, text=True, timeout=120)
    return json.loads(r.stdout)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--stdin":  # test mode: <json on stdin> --stdin <device>
        print("\n".join(render(sys.argv[2], json.load(sys.stdin))))
        return
    lines = ["# TYPE smartctl_device_smart_status gauge"]
    for dev in smartctl_json("--scan").get("devices", []):
        name = os.path.basename(dev["name"])
        try:
            lines += render(name, smartctl_json("-a", "-d", dev["type"], dev["name"]))
        except Exception as e:  # one bad disk must not hide the others
            print(f"{name}: {e}", file=sys.stderr)
    lines.append("# TYPE smartctl_textfile_timestamp_seconds gauge")
    lines.append(f"smartctl_textfile_timestamp_seconds {int(time.time())}")
    fd, tmp = tempfile.mkstemp(dir=OUT_DIR, prefix=".smart.")
    with os.fdopen(fd, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, os.path.join(OUT_DIR, "smart.prom"))


if __name__ == "__main__":
    main()
