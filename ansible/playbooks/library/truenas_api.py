#!/usr/bin/python
# Declarative TrueNAS middleware resources over the JSON-RPC websocket API (TrueNAS 25.x).
# Client: module_utils/truenas_ws.py (standard library only).

DOCUMENTATION = r"""
module: truenas_api
short_description: Manage TrueNAS SCALE resources through the websocket API
description:
  - Runs on the controller (connection local) and talks to C(wss://<host>/api/current) with an API key.
  - One module call = one connection = one login. TrueNAS allows about 20 auth attempts per 60 s (then a
    10 minute lockout), so pass a whole namespace as C(items), and several sections as C(batch), instead of
    looping over the module.
options:
  url: {type: str, required: true, description: "wss://host/api/current"}
  api_user: {type: str, required: true}
  api_key: {type: str, required: true, no_log: true}
  verify_ssl: {type: bool, default: false}
  batch:
    type: list
    elements: dict
    description: "Several sections over one connection; each element takes the section options below plus
      an optional C(name). When set, the top-level section options are ignored."
  mode: {type: str, choices: [collection, config, call], default: collection}
  ns: {type: str, description: "Namespace, e.g. sharing.nfs, system.general"}
  key: {type: list, elements: str, description: "collection: fields that identify an item (query filter)"}
  items: {type: list, elements: dict, description: "collection: desired items; optional per-item state: absent"}
  update: {type: bool, default: true, description: "collection: false = only create missing items"}
  data: {type: dict, description: "config: desired settings"}
  job: {type: bool, default: false, description: "create/update calls are middleware jobs"}
  method: {type: str, description: "call: method name (read-only calls, never reports changed)"}
  params: {type: list, default: [], description: "call: positional params"}
  report_unmanaged: {type: bool, default: false, description: "collection: list existing items not in items"}
  secret_keys: {type: list, elements: str, default: [], description: "keys masked in diff/output (any depth)"}
"""

import copy
import sys

from ansible.module_utils.basic import AnsibleModule

try:
    from ansible.module_utils.truenas_ws import Client, TrueNASError
except ImportError:  # running the file directly for tests
    sys.path.insert(0, __file__.rsplit("/", 2)[0] + "/module_utils")
    from truenas_ws import Client, TrueNASError

MASK = "********"

SECTION_DEFAULTS = {
    "name": None,
    "mode": "collection",
    "ns": None,
    "key": None,
    "items": None,
    "update": True,
    "data": None,
    "job": False,
    "method": None,
    "params": [],
    "report_unmanaged": False,
    "secret_keys": [],
}


class SectionError(Exception):
    pass


# -- comparison --------------------------------------------------------------------------------


def _scalar_eq(want, have):
    if isinstance(have, dict) and "id" in have and not isinstance(want, dict):
        have = have["id"]  # reference objects (ssh_credentials, group, ...) compare on id
    if isinstance(want, bool) or isinstance(have, bool):
        return want == have
    if want == have:
        return True
    if isinstance(want, (int, float, str)) and isinstance(have, (int, float, str)):
        sw, sh = str(want), str(have)
        if sw.isdigit() and sh.isdigit():
            return int(sw) == int(sh)  # cron fields: "0" == "00"
        return sw == sh
    return False


def matches(want, have):
    """True when every key in `want` has the same value in `have` (subset compare, recursive)."""
    if isinstance(want, dict):
        if not isinstance(have, dict):
            return False
        return all(k in have and matches(v, have[k]) for k, v in want.items())
    if isinstance(want, list):
        if not isinstance(have, list) or len(want) != len(have):
            return False
        if all(not isinstance(x, (dict, list)) for x in want + have):
            return sorted(map(str, want)) == sorted(map(str, have))  # lists of scalars: order-free
        return all(matches(w, h) for w, h in zip(want, have))
    if want is None:
        return have in (None, "")
    return _scalar_eq(want, have)


def project(want, have):
    """`have` reduced to the keys present in `want` (for a readable diff)."""
    if isinstance(want, dict) and isinstance(have, dict):
        return {k: project(v, have.get(k)) for k, v in want.items()}
    if isinstance(have, dict) and "id" in have and not isinstance(want, dict):
        return have["id"]
    return have


def mask(obj, secret_keys):
    if isinstance(obj, dict):
        return {k: (MASK if k in secret_keys and v not in (None, "") else mask(v, secret_keys)) for k, v in obj.items()}
    if isinstance(obj, list):
        return [mask(v, secret_keys) for v in obj]
    return obj


def label(item, key):
    return "|".join(str(item.get(k)) for k in key)


# -- sections ----------------------------------------------------------------------------------


def run_collection(c, s, check):
    ns, key, secret = s["ns"], s["key"], s["secret_keys"]
    if not ns or not key:
        raise SectionError("collection mode needs ns and key")
    changed, results, ids = False, [], {}
    before_all, after_all = {}, {}
    wanted = set()
    for raw in s["items"] or []:
        item = copy.deepcopy(raw)
        state = item.pop("state", "present")
        lbl = label(item, key)
        wanted.add(lbl)
        found = c.call(f"{ns}.query", [[k, "=", item[k]] for k in key])
        if len(found) > 1:
            raise SectionError(f"{ns}: {len(found)} items match {lbl}, key is not unique")
        have = found[0] if found else None
        res = {"item": lbl, "id": have["id"] if have else None, "action": "none"}
        if state == "absent":
            if have:
                res["action"] = "delete"
                before_all[lbl], after_all[lbl] = mask(project(item, have), secret), None
                if not check:
                    c.call(f"{ns}.delete", have["id"])
        elif not have:
            res["action"] = "create"
            before_all[lbl], after_all[lbl] = None, mask(item, secret)
            if not check:
                created = c.call(f"{ns}.create", item, job=s["job"])
                res["id"] = created.get("id") if isinstance(created, dict) else created
        elif s["update"] and not matches(item, have):
            res["action"] = "update"
            before_all[lbl], after_all[lbl] = mask(project(item, have), secret), mask(item, secret)
            upd = {k: v for k, v in item.items() if not matches(v, have.get(k))}
            if not check:
                c.call(f"{ns}.update", have["id"], upd, job=s["job"])
        changed = changed or res["action"] != "none"
        results.append(res)
        ids[lbl] = res["id"]
    out = {"changed": changed, "results": results, "ids": ids, "before": before_all, "after": after_all}
    if s["report_unmanaged"]:
        out["unmanaged"] = [{"id": h["id"], "item": label(h, key)} for h in c.call(f"{ns}.query") if label(h, key) not in wanted]
    return out


def run_config(c, s, check):
    ns, data, secret = s["ns"], s["data"] or {}, s["secret_keys"]
    if not ns:
        raise SectionError("config mode needs ns")
    have = c.call(f"{ns}.config")
    if matches(data, have):
        return {"changed": False, "before": {}, "after": {}}
    upd = {k: v for k, v in data.items() if not matches(v, have.get(k))}
    if not check:
        c.call(f"{ns}.update", upd, job=s["job"])
    return {
        "changed": True,
        "updated_keys": sorted(upd),
        "before": mask(project(upd, have), secret),
        "after": mask(upd, secret),
    }


def run_call(c, s, check):
    if not s["method"]:
        raise SectionError("call mode needs method")
    return {"changed": False, "result": c.call(s["method"], *s["params"], job=s["job"]), "before": {}, "after": {}}


RUNNERS = {"collection": run_collection, "config": run_config, "call": run_call}


def run_section(c, raw, check):
    unknown = set(raw) - set(SECTION_DEFAULTS)
    if unknown:
        raise SectionError(f"unknown section options: {sorted(unknown)}")
    s = dict(SECTION_DEFAULTS, **{k: v for k, v in raw.items() if v is not None})
    if s["mode"] not in RUNNERS:
        raise SectionError(f"bad mode {s['mode']}")
    out = RUNNERS[s["mode"]](c, s, check)
    out["name"] = s["name"] or s["ns"] or s["method"]
    return out


def main():
    m = AnsibleModule(
        argument_spec=dict(
            url=dict(type="str", required=True),
            api_user=dict(type="str", required=True),
            api_key=dict(type="str", required=True, no_log=True),
            verify_ssl=dict(type="bool", default=False),
            batch=dict(type="list", elements="dict"),
            mode=dict(type="str", choices=["collection", "config", "call"], default="collection"),
            ns=dict(type="str"),
            key=dict(type="list", elements="str"),
            items=dict(type="list", elements="dict"),
            update=dict(type="bool", default=True),
            data=dict(type="dict"),
            job=dict(type="bool", default=False),
            method=dict(type="str"),
            params=dict(type="list", default=[]),
            report_unmanaged=dict(type="bool", default=False),
            secret_keys=dict(type="list", elements="str", default=[], no_log=False),
        ),
        supports_check_mode=True,
    )
    p = m.params
    single = {k: p[k] for k in SECTION_DEFAULTS if k in p}
    sections = p["batch"] if p["batch"] else [single]
    outs = []
    try:
        with Client(p["url"], verify_ssl=p["verify_ssl"]) as c:
            c.login_api_key(p["api_user"], p["api_key"])
            for s in sections:
                outs.append(run_section(c, s, m.check_mode))
    except (TrueNASError, SectionError, OSError, ConnectionError) as e:
        m.fail_json(msg=str(e), sections=[{k: v for k, v in o.items() if k not in ("before", "after")} for o in outs])

    diffs = [
        {"before_header": o["name"], "after_header": o["name"], "before": o["before"], "after": o["after"]}
        for o in outs
        if o["changed"]
    ]
    clean = [{k: v for k, v in o.items() if k not in ("before", "after")} for o in outs]
    result = {"changed": any(o["changed"] for o in outs), "diff": diffs}
    if p["batch"]:
        result["sections"] = {o["name"]: o for o in clean}
    else:
        result.update(clean[0])
    m.exit_json(**result)


if __name__ == "__main__":
    main()
