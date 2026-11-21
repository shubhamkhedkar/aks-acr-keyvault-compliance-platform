"""Repository-level guardrails that keep the project honest."""

import json
import re
import subprocess
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
TEXT_SUFFIXES = {".md", ".py", ".tf", ".hcl", ".yml", ".yaml", ".json", ".rb", ".sh", ".toml", ".txt", ""}


def tracked_files():
    out = subprocess.run(["git", "ls-files", "-co", "--exclude-standard"], cwd=ROOT, capture_output=True, text=True)
    return [ROOT / p for p in out.stdout.splitlines() if (ROOT / p).is_file()]


def test_configmap_seed_matches_app_seed():
    a = json.loads((ROOT / "app/seed/flags.json").read_text())
    b = json.loads((ROOT / "deploy/kustomize/base/flags.json").read_text())
    assert a == b, "deploy/kustomize/base/flags.json must mirror app/seed/flags.json"


def test_no_github_actions_workflows():
    workflows = ROOT / ".github" / "workflows"
    assert not workflows.exists() or not any(workflows.iterdir())


def test_wording_policy():
    banned = re.compile(r"\b(" + "learn" + "ing|" + "begin" + "ner)\b", re.IGNORECASE)
    offenders = []
    for path in tracked_files():
        if path.suffix in TEXT_SUFFIXES or path.name in {"Makefile", "Dockerfile"}:
            text = path.read_text(encoding="utf-8", errors="ignore")
            if banned.search(text):
                offenders.append(str(path.relative_to(ROOT)))
    assert offenders == []


def test_no_secrets_in_terraform_state_paths():
    for tf in (ROOT / "terraform").rglob("*.tf"):
        text = tf.read_text()
        assert "azurerm_key_vault_secret" not in text, f"{tf}: secret values would land in state"
        assert not re.search(r"admin_enabled\s*=\s*true", text)
        assert "client_secret" not in text


def _load(path):
    return yaml.safe_load((ROOT / path).read_text())


def test_pipeline_shape():
    pipe = _load("azure-pipelines.yml")
    stages = [s["stage"] for s in pipe["stages"]]
    assert stages == ["Validate", "Build", "Infrastructure", "Deploy", "Verify"]
    by_name = {s["stage"]: s for s in pipe["stages"]}
    for gated in ("Build", "Infrastructure"):
        assert "isMain" in by_name[gated]["condition"], f"{gated} must only run on main"
    jobs = {j.get("job") or j.get("deployment"): j for j in by_name["Infrastructure"]["jobs"]}
    assert jobs["apply"]["environment"] == "flagpost-prod-infra" and jobs["apply"]["dependsOn"] == "plan"
    deploy = by_name["Deploy"]["jobs"][0]
    assert deploy["environment"] == "flagpost-prod"


def test_pipeline_templates_exist_and_parse():
    text = (ROOT / "azure-pipelines.yml").read_text()
    refs = set(re.findall(r"template:\s*(\S+)", text))
    assert refs, "expected template references"
    for ref in refs:
        assert (ROOT / ref).is_file(), ref
        assert _load(ref) is not None


def test_pipeline_never_uses_static_credentials():
    for path in [ROOT / "azure-pipelines.yml", *sorted((ROOT / "pipelines").rglob("*.yml"))]:
        text = path.read_text()
        assert "az login" not in text
        assert "--password" not in text
        assert "ARM_CLIENT_SECRET" not in text
