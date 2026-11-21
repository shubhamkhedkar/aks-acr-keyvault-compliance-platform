import pytest

from flagpost.rules import Flag, ValidationError, bucket, evaluate, parse_flag


def test_parse_valid_flag_normalises_tenants():
    flag = parse_flag("new-ui", {"enabled": True, "rollout_percent": 10, "allow_tenants": ["b", "a", "a"]})
    assert flag.allow_tenants == ("a", "b")
    assert flag.to_dict()["allow_tenants"] == ["a", "b"]


@pytest.mark.parametrize(
    ("key", "doc", "message"),
    [
        ("Bad_Key", {}, "flag key"),
        ("ok-key", [], "JSON object"),
        ("ok-key", {"colour": "red"}, "unknown fields"),
        ("ok-key", {"key": "other"}, "does not match"),
        ("ok-key", {"enabled": "yes"}, "boolean"),
        ("ok-key", {"rollout_percent": 101}, "between 0 and 100"),
        ("ok-key", {"rollout_percent": True}, "between 0 and 100"),
        ("ok-key", {"description": "x" * 281}, "280"),
        ("ok-key", {"owner": "has space"}, "owner"),
        ("ok-key", {"allow_tenants": "contoso"}, "list"),
        ("ok-key", {"deny_tenants": ["bad tenant"]}, "invalid tenant"),
        ("ok-key", {"allow_tenants": ["a"], "deny_tenants": ["a"]}, "both allowed and denied"),
    ],
)
def test_parse_rejects_invalid(key, doc, message):
    with pytest.raises(ValidationError, match=message):
        parse_flag(key, doc)


def test_bucket_is_stable_and_in_range():
    values = {bucket("checkout-v2", f"user-{i}") for i in range(500)}
    assert all(0 <= v < 100 for v in values)
    assert bucket("checkout-v2", "user-1") == bucket("checkout-v2", "user-1")
    assert len(values) > 80  # spreads across buckets


def test_rollout_percentage_is_roughly_honoured():
    flag = Flag(key="half", enabled=True, rollout_percent=50)
    on = sum(evaluate(flag, "t", f"user-{i}")[0] for i in range(2000))
    assert 900 < on < 1100


@pytest.mark.parametrize(
    ("flag", "tenant", "expected"),
    [
        (Flag(key="f1", enabled=False, rollout_percent=100), "a", (False, "flag-disabled")),
        (Flag(key="f1", enabled=True, rollout_percent=100, deny_tenants=("a",)), "a", (False, "tenant-denied")),
        (Flag(key="f1", enabled=True, rollout_percent=0, allow_tenants=("a",)), "a", (True, "tenant-allowed")),
        (Flag(key="f1", enabled=True, rollout_percent=100), "a", (True, "rollout")),
        (Flag(key="f1", enabled=True, rollout_percent=0), "a", (False, "outside-rollout")),
    ],
)
def test_evaluation_order(flag, tenant, expected):
    assert evaluate(flag, tenant, "user-1") == expected
