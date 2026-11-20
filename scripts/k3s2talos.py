#!/usr/bin/env python3
"""Port a k3s app directory (k8s/) to the Talos Flux tree (k8s-talos/apps/).

Subcommands:
  convert      copy an app's manifests, converting what differs on Talos:
               Ingress -> HTTPRoute on gateway/main, SopsSecret -> SOPS-encrypted Secret,
               LoadBalancer Service -> ClusterIP, optional replica override
  migrate-jobs write the one-off PVC copy Jobs (export on k3s, import on Talos),
               staged as tar files on the NAS dataset tank-data/k8s-migration

Run from the repo root inside a venv with PyYAML (see scripts/requirements.txt):
  python3 scripts/k3s2talos.py convert k8s/mediaserver/jackett mediaserver --replicas 0
  python3 scripts/k3s2talos.py migrate-jobs mediaserver jackett jackett-pvc-pve
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml

TALOS_APPS = Path("k8s-talos/apps")
GATEWAY = {"name": "main", "namespace": "gateway", "sectionName": "https"}
NAS = "nas.enricoruggieri.com"
STAGING = "/tank-data/k8s-migration"
# nginx annotations with no Gateway API counterpart needed (see the migration plan)
IGNORED_ANNOTATIONS = {
    "cert-manager.io/cluster-issuer",
    "nginx.ingress.kubernetes.io/proxy-body-size",
    "nginx.ingress.kubernetes.io/enable-real-ip",
    "nginx.ingress.kubernetes.io/proxy-send-timeout",
}
TIMEOUT_ANNOTATION = "nginx.ingress.kubernetes.io/proxy-read-timeout"
WORKLOADS = {"Deployment", "StatefulSet"}


def _str_presenter(dumper, data):
    style = "|" if "\n" in data else None
    return dumper.represent_scalar("tag:yaml.org,2002:str", data, style=style)


yaml.SafeDumper.add_representer(str, _str_presenter)


def dump(obj):
    return yaml.safe_dump(obj, sort_keys=False, default_flow_style=False)


def warn(msg):
    print(f"WARN: {msg}", file=sys.stderr)


def split_docs(text):
    """Split a multi-document YAML file, keeping each document's original text.
    Empty and comment-only documents are dropped."""
    docs = re.split(r"^---[ \t]*\n", text, flags=re.M)
    return [d for d in docs if yaml.safe_load(d)]


def tracked_files(src):
    out = subprocess.run(
        ["git", "ls-files", "--", str(src)], check=True, capture_output=True, text=True
    ).stdout.split()
    return sorted(Path(f) for f in out if f.endswith((".yaml", ".yml")))


def ingress_to_httproutes(ing):
    meta = ing["metadata"]
    ann = meta.get("annotations") or {}
    for key in ann:
        if key not in IGNORED_ANNOTATIONS and key != TIMEOUT_ANNOTATION:
            warn(f"Ingress {meta['name']}: annotation {key} not converted")
    timeout = ann.get(TIMEOUT_ANNOTATION)

    routes = []
    for rule in ing["spec"].get("rules", []):
        rules = []
        for path in rule.get("http", {}).get("paths", []):
            backend = path["backend"]["service"]
            route_rule = {}
            if path.get("path", "/") != "/":
                route_rule["matches"] = [
                    {"path": {"type": "PathPrefix", "value": path["path"]}}
                ]
            route_rule["backendRefs"] = [
                {"name": backend["name"], "port": backend["port"]["number"]}
            ]
            if timeout:
                route_rule["timeouts"] = {"request": f"{timeout}s"}
            rules.append(route_rule)
        name = meta["name"] if not routes else f"{meta['name']}-{len(routes)}"
        routes.append(
            {
                "apiVersion": "gateway.networking.k8s.io/v1",
                "kind": "HTTPRoute",
                "metadata": {"name": name, "namespace": meta["namespace"]},
                "spec": {
                    "parentRefs": [GATEWAY],
                    "hostnames": [rule["host"]],
                    "rules": rules,
                },
            }
        )
    return routes


def sops_secret_to_secrets(path):
    plain = subprocess.run(
        ["sops", "--decrypt", str(path)], check=True, capture_output=True, text=True
    ).stdout
    src = yaml.safe_load(plain)
    ns = src["metadata"]["namespace"]
    secrets = []
    for tpl in src["spec"]["secretTemplates"]:
        meta = {"name": tpl["name"], "namespace": ns}
        if tpl.get("labels"):
            meta["labels"] = tpl["labels"]
        secret = {"apiVersion": "v1", "kind": "Secret", "metadata": meta}
        if tpl.get("type"):
            secret["type"] = tpl["type"]
        for field in ("stringData", "data"):
            if tpl.get(field):
                secret[field] = tpl[field]
        secrets.append(secret)
    return secrets


def write_encrypted(dest, docs):
    dest.write_text("---\n".join(dump(d) for d in docs))
    try:
        subprocess.run(["sops", "--encrypt", "--in-place", str(dest)], check=True)
    except subprocess.CalledProcessError:
        dest.unlink()  # never leave a plaintext secret behind
        raise


def convert_doc(text, replicas):
    """Return the document text for Talos, or None to drop it (Ingress, handled by the caller)."""
    obj = yaml.safe_load(text)
    kind = obj.get("kind")
    if kind == "Service" and obj.get("spec", {}).get("type") == "LoadBalancer":
        obj["spec"]["type"] = "ClusterIP"
        for key in ("loadBalancerIP", "externalTrafficPolicy", "allocateLoadBalancerNodePorts"):
            obj["spec"].pop(key, None)
        ann = obj["metadata"].get("annotations") or {}
        for key in [k for k in ann if "metallb" in k or "lbipam" in k]:
            del ann[key]
        if not ann:
            obj["metadata"].pop("annotations", None)
        return dump(obj)
    if kind in WORKLOADS and replicas is not None:
        obj["spec"]["replicas"] = replicas
        return dump(obj)
    return text if text.endswith("\n") else text + "\n"


def add_to_group(group, app):
    group_dir = TALOS_APPS / group
    kfile = group_dir / "kustomization.yaml"
    if not kfile.exists():
        sys.exit(f"{kfile} missing: create the group (namespace + kustomization) first")
    k = yaml.safe_load(kfile.read_text())
    if app not in k["resources"]:
        k["resources"].append(app)
        kfile.write_text(dump(k))


def cmd_convert(args):
    src = Path(args.src)
    app = args.name or src.name
    dest = TALOS_APPS / args.group / app
    if dest.exists() and not args.force:
        sys.exit(f"{dest} exists (use --force to overwrite)")
    dest.mkdir(parents=True, exist_ok=True)

    resources, routes = [], []
    for f in tracked_files(src):
        if f.name in args.exclude:
            continue
        docs = split_docs(f.read_text())
        if not docs:
            continue
        kinds = [yaml.safe_load(d).get("kind") for d in docs]
        if "SopsSecret" in kinds:
            if set(kinds) != {"SopsSecret"}:
                sys.exit(f"{f}: SopsSecret mixed with other kinds, split it first")
            out = dest / "sops_secret.yaml"
            write_encrypted(out, sops_secret_to_secrets(f))
            resources.append(out.name)
            continue

        kept = []
        for text in docs:
            obj = yaml.safe_load(text)
            if obj.get("kind") == "Ingress":
                routes += ingress_to_httproutes(obj)
                continue
            kept.append(convert_doc(text, args.replicas))
        if kept:
            (dest / f.name).write_text("---\n".join(kept))
            resources.append(f.name)

    if routes:
        (dest / "httproute.yaml").write_text("---\n".join(dump(r) for r in routes))
        resources.append("httproute.yaml")
    kustomization = {
        "apiVersion": "kustomize.config.k8s.io/v1beta1",
        "kind": "Kustomization",
        "resources": resources,
    }
    (dest / "kustomization.yaml").write_text(dump(kustomization))
    add_to_group(args.group, app)
    print(f"{src} -> {dest}: {', '.join(resources)}")
    for r in routes:
        print(f"  host {r['spec']['hostnames'][0]}")


def copy_job(name, ns, pvc, mount, script):
    return {
        "apiVersion": "batch/v1",
        "kind": "Job",
        "metadata": {"name": name, "namespace": ns},
        "spec": {
            # no TTL: GitOps would recreate a deleted Job and run it again
            "backoffLimit": 2,
            "template": {
                "spec": {
                    "restartPolicy": "Never",
                    "containers": [
                        {
                            "name": "copy",
                            "image": "alpine:3.22",
                            "command": ["/bin/sh", "-c"],
                            "args": [script],
                            "volumeMounts": [
                                {"name": "data", "mountPath": mount},
                                {"name": "staging", "mountPath": "/staging"},
                            ],
                        }
                    ],
                    "volumes": [
                        {"name": "data", "persistentVolumeClaim": {"claimName": pvc}},
                        {"name": "staging", "nfs": {"server": NAS, "path": STAGING}},
                    ],
                }
            },
        },
    }


EXPORT = """set -eu
apk add --no-cache tar >/dev/null
out=/staging/{app}/{pvc}.tar
if [ -e "$out.done" ]; then echo "already exported"; exit 0; fi
mkdir -p /staging/{app}
tar --numeric-owner --xattrs -C /src -cf "$out" .
sha256sum "$out" > "$out.sha256"
touch "$out.done"
ls -l "$out"
"""

IMPORT = """set -eu
apk add --no-cache tar >/dev/null
in=/staging/{app}/{pvc}.tar
if [ -e /dst/.k3s-migrated ]; then echo "already imported"; exit 0; fi
i=0
until [ -e "$in.done" ]; do
  i=$((i+1)); [ $i -gt 720 ] && {{ echo "export not found after 2h"; exit 1; }}
  sleep 10
done
cd /staging/{app} && sha256sum -c {pvc}.tar.sha256
tar --numeric-owner --xattrs -C /dst -xpf "$in"
date -u > /dst/.k3s-migrated
ls -la /dst
"""


def cmd_migrate_jobs(args):
    k3s_dir = Path(args.k3s_dir or f"k8s/{args.group}/{args.app}")
    talos_dir = TALOS_APPS / args.group / args.app
    ns = args.namespace or args.group
    exports, imports = [], []
    for pvc in args.pvcs:
        fmt = {"app": args.app, "pvc": pvc}
        exports.append(copy_job(f"migrate-export-{pvc}", ns, pvc, "/src", EXPORT.format(**fmt)))
        imports.append(copy_job(f"migrate-import-{pvc}", ns, pvc, "/dst", IMPORT.format(**fmt)))

    header = "# One-off PVC copy to Talos (scripts/k3s2talos.py migrate-jobs). Remove after the cutover.\n"
    (k3s_dir / "migrate-export.yaml").write_text(header + "---\n".join(dump(j) for j in exports))
    (talos_dir / "migrate-import.yaml").write_text(header + "---\n".join(dump(j) for j in imports))
    kfile = talos_dir / "kustomization.yaml"
    k = yaml.safe_load(kfile.read_text())
    if "migrate-import.yaml" not in k["resources"]:
        k["resources"].append("migrate-import.yaml")
        kfile.write_text(dump(k))
    print(f"wrote {k3s_dir}/migrate-export.yaml and {talos_dir}/migrate-import.yaml")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("convert", help="port an app directory")
    c.add_argument("src", help="k3s app directory, e.g. k8s/mediaserver/jackett")
    c.add_argument("group", help="Talos group under k8s-talos/apps/")
    c.add_argument("--name", help="app folder name (default: source folder name)")
    c.add_argument("--replicas", type=int, help="override replicas of Deployments/StatefulSets")
    c.add_argument("--exclude", action="append", default=[], help="file name to skip (repeatable)")
    c.add_argument("--force", action="store_true")
    c.set_defaults(func=cmd_convert)

    m = sub.add_parser("migrate-jobs", help="write PVC export/import Jobs")
    m.add_argument("group")
    m.add_argument("app")
    m.add_argument("pvcs", nargs="+", help="PVC names (same name on both clusters)")
    m.add_argument("--namespace", help="default: the group name")
    m.add_argument("--k3s-dir", help="default: k8s/<group>/<app>")
    m.set_defaults(func=cmd_migrate_jobs)

    args = p.parse_args()
    if not Path(".sops.yaml").exists():
        sys.exit("run from the repo root")
    os.environ.setdefault("SOPS_AGE_KEY_FILE", os.path.expanduser("~/.sops/age_key.txt"))
    args.func(args)


if __name__ == "__main__":
    main()
