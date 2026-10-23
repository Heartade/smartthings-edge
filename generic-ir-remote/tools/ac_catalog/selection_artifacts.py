#!/usr/bin/env python3
"""Generate the single AC protocol/model selector from the encoder catalog."""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CAPABILITY_ID = "againmusic09479.acProtocolSelection"
CAPABILITY_KEY = "acProtocolSelection"
CAPABILITY_FOLDER = "ac-protocol-selection"
CAPABILITY_PROFILES = [
    "ac-learned-state",
    "ac-protocol",
    "ac-protocol-generated",
    "ac-protocol-learning",
]

def model_label(protocol: str, model: dict) -> tuple[str, str]:
    family = protocol.replace("_", " ")
    if model["name"] == "default":
        return family, family

    name = model["name"]
    shortened = name
    for prefix in (
        "kToshibaGenericRemote_",
        "kPanasonic",
        "kVoltas",
    ):
        if shortened.startswith(prefix):
            shortened = shortened[len(prefix):]
            break
    if shortened.startswith("k"):
        shortened = shortened[1:]

    if protocol == "TOSHIBA_AC":
        family = "Toshiba AC"
        shortened = "Generic " + shortened
    elif protocol == "PANASONIC_AC":
        family = "Panasonic AC"
    elif protocol == "VOLTAS":
        family = "Voltas"

    en = f"{family} {model['value']}: {shortened}"
    ko = f"{family} {model['value']}: {shortened}"
    if len(en) > 36:
        # The display label is intentionally concise; the model table retains
        # the full upstream enum names for reference.
        family = family.replace("MITSUBISHI HEAVY", "MHI").replace("MITSUBISHI", "Mitsu")
        en = f"{family} {model['value']}: {shortened}"
        ko = en
    if len(en) > 36:
        raise ValueError(f"AC selector label exceeds 36 characters: {en}")
    return en, ko


def choices(manifest: dict) -> list[dict]:
    result = [{
        "key": "learned_state", "protocol_key": "learned_state", "model": 0,
        "en": "Learn AC states", "ko": "AC 상태 학습", "learned": True,
    }]
    for entry in manifest["protocols"]:
        protocol_key = "irac_" + entry["protocol"].lower()
        for model in entry["models"]:
            key = f"{protocol_key}_m{model['value']}"
            en, ko = model_label(entry["protocol"], model)
            result.append({
                "key": key,
                "protocol_key": protocol_key,
                "model": model["value"],
                "en": en,
                "ko": ko,
                "learned": False,
            })
    if len({item["key"] for item in result}) != len(result):
        raise ValueError("Duplicate AC selection key")
    if any(len(item["key"]) > 36 for item in result):
        raise ValueError("AC selection key exceeds SmartThings string limit")
    return result


def write_capability_files(items: list[dict]) -> None:
    folder = ROOT / "capabilities" / CAPABILITY_FOLDER
    folder.mkdir(parents=True, exist_ok=True)
    values = [item["key"] for item in items]
    definition = {
        "name": "AC Protocol Selection",
        "attributes": {
            "selection": {
                "schema": {
                    "type": "object",
                    "properties": {"value": {"type": "string", "enum": values, "maxLength": 36}},
                    "additionalProperties": False,
                    "required": ["value"],
                },
                "setter": "setSelection",
            }
        },
        "commands": {
            "setSelection": {
                "arguments": [{
                    "name": "selection",
                    "optional": False,
                    "schema": {"type": "string", "enum": values, "maxLength": 36},
                }],
                "name": "setSelection",
            }
        },
    }
    (folder / "capability.json").write_text(json.dumps(definition, indent=2) + "\n", encoding="utf-8")

    alternatives = [
        {
            "key": item["key"],
            "value": "{{i18n.attributes.selection.i18n.value." + item["key"] + ".label}}",
            "type": "active",
        }
        for item in items
    ]
    presentation = {
        "dashboard": {"states": [], "actions": []},
        "detailView": [{
            "label": "{{i18n.attributes.selection.label}}",
            "displayType": "list",
            "list": {
                "command": {"name": "setSelection", "alternatives": alternatives},
                "state": {"value": "selection.value", "valueType": "string", "alternatives": alternatives},
            },
        }],
        "automation": {"conditions": [], "actions": []},
        "version": 1,
    }
    (folder / "presentation.json").write_text(json.dumps(presentation, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    for locale in ("en", "ko"):
        label = "AC protocol / model" if locale == "en" else "에어컨 프로토콜 / 모델"
        command_label = "Select AC protocol and model" if locale == "en" else "에어컨 프로토콜 및 모델 선택"
        value_labels = {item["key"]: {"label": item[locale]} for item in items}
        translation = {
            "tag": locale,
            "label": "AC protocol selection" if locale == "en" else "에어컨 프로토콜 선택",
            "attributes": {
                "selection": {
                    "label": label,
                    "i18n": {"value": value_labels},
                }
            },
            "commands": {"setSelection": {"label": command_label}},
        }
        (folder / f"{locale}.json").write_text(json.dumps(translation, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def write_lua_index(items: list[dict]) -> None:
    lines = ["-- Generated from tools/ac_catalog/manifest.json.", "return {"]
    for item in items:
        lines.append(
            "  {key=" + json.dumps(item["key"]) + ", protocol_key=" +
            json.dumps(item["protocol_key"]) + ", model=" + str(item["model"]) +
            ", learned=" + ("true" if item["learned"] else "false") + "},"
        )
    lines.append("}")
    (ROOT / "src" / "ac" / "selection_index.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")


def update_profiles() -> None:
    registration_manifest = json.loads(
        (ROOT / "capabilities" / "manifest.json").read_text(encoding="utf-8-sig")
    )
    registered = next(
        (item for item in registration_manifest["capabilities"] if item.get("key") == CAPABILITY_KEY),
        None,
    )
    capability_id = registered.get("registeredId", CAPABILITY_ID) if registered else CAPABILITY_ID
    capability_line = f"      - id: {capability_id}\n        version: 1"
    for name in CAPABILITY_PROFILES:
        path = ROOT / "profiles" / f"{name}.yaml"
        lines = path.read_text(encoding="utf-8-sig").splitlines()
        output: list[str] = []
        inserted = False
        skip_pref = False
        pref_blocks: list[list[str]] = []
        in_preferences = False
        for line in lines:
            if line == "preferences:":
                in_preferences = True
                output.append(line)
                continue
            if in_preferences and line.startswith("  - title:"):
                pref_blocks.append([line])
                continue
            if in_preferences and pref_blocks and (line.startswith("    ") or not line.strip()):
                pref_blocks[-1].append(line)
                continue
            if in_preferences and line.strip():
                in_preferences = False
            output.append(line)

        if pref_blocks:
            kept: list[list[str]] = []
            for block in pref_blocks:
                joined = "\n".join(block)
                if re.search(r"(?m)^    name: (acProtocol|acModel)$", joined):
                    continue
                kept.append(block)
            if kept:
                # Rebuild preferences at its original position, retaining all
                # unrelated preferences such as temperature unit and learning.
                output = [line for line in output if line != "preferences:"]
                insert_at = next((i for i, line in enumerate(output) if line.startswith("  - title: AC temperature unit")), None)
                if insert_at is None:
                    # No AC temperature preference was present; append blocks
                    # after device components and categories.
                    output.append("preferences:")
                    insert_at = len(output)
                else:
                    output.insert(insert_at, "preferences:")
                rebuilt = []
                for block in kept:
                    rebuilt.extend(block)
                output[insert_at + 1:insert_at + 1] = rebuilt
            else:
                output = [line for line in output if line != "preferences:"]

        # Collapse duplicate selector entries/version lines left by older runs
        # of this generator, while preserving the first selector in place.
        normalized: list[str] = []
        selector_seen = False
        i = 0
        while i < len(output):
            line = output[i]
            is_selector = line.startswith("      - id: ") and "acProtocolSelection" in line
            if is_selector and selector_seen:
                i += 1
                if i < len(output) and output[i] == "        version: 1": i += 1
                continue
            if is_selector:
                selector_seen = True
            if line == "        version: 1" and normalized and normalized[-1] == line:
                i += 1
                continue
            normalized.append(line)
            i += 1
        output = normalized

        # Add the selector immediately after refresh, before learning controls.
        if not selector_seen:
            for i, line in enumerate(output):
                if line == "        version: 1" and i > 0 and output[i - 1] == "      - id: refresh":
                    output[i + 1:i + 1] = capability_line.splitlines()
                    inserted = True
                    break
        else:
            inserted = True
        if not inserted:
            raise ValueError(f"Could not add AC selector to {path}")
        path.write_text("\n".join(output) + "\n", encoding="utf-8", newline="\n")


def update_capability_manifest() -> None:
    path = ROOT / "capabilities" / "manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8-sig"))
    entry = next((item for item in manifest["capabilities"] if item.get("key") == CAPABILITY_KEY), None)
    if entry is None:
        entry = {
            "key": CAPABILITY_KEY,
            "registeredId": CAPABILITY_ID,
            "registeredVersion": 1,
            "registrationPending": True,
            "definition": f"{CAPABILITY_FOLDER}/capability.json",
            "presentation": f"{CAPABILITY_FOLDER}/presentation.json",
            "translations": {"en": f"{CAPABILITY_FOLDER}/en.json", "ko": f"{CAPABILITY_FOLDER}/ko.json"},
            "profiles": CAPABILITY_PROFILES,
        }
        manifest["capabilities"].append(entry)
    else:
        entry["definition"] = f"{CAPABILITY_FOLDER}/capability.json"
        entry["presentation"] = f"{CAPABILITY_FOLDER}/presentation.json"
        entry["translations"] = {"en": f"{CAPABILITY_FOLDER}/en.json", "ko": f"{CAPABILITY_FOLDER}/ko.json"}
        entry["profiles"] = CAPABILITY_PROFILES
    path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def generate(manifest_path: Path | None = None) -> list[dict]:
    manifest_path = manifest_path or ROOT / "tools" / "ac_catalog" / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    items = choices(manifest)
    write_capability_files(items)
    write_lua_index(items)
    update_profiles()
    update_capability_manifest()
    return items


if __name__ == "__main__":
    result = generate()
    print(f"Generated AC selector with {len(result)} choices")
