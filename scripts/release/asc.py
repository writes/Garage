#!/usr/bin/env python3
"""Operate Garage's App Store Connect release path without third-party HTTP/JWT code.

The easy-to-miss authentication detail is that ``cryptography`` returns an ES256
signature in ASN.1 DER form, while a JSON Web Token requires a 64-byte JOSE
signature: the 32-byte big-endian ``r`` value followed by the 32-byte
big-endian ``s`` value.  Sending the DER bytes yields a misleading 401 from
App Store Connect.  :func:`build_jwt` therefore converts the signature before
base64url encoding it.

Only Python 3.12's standard library and ``cryptography`` are used.  This tool
intentionally never prints, logs, or writes private key material or JWTs.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping, Sequence
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urljoin
from urllib.request import Request, urlopen

CRYPTOGRAPHY_IMPORT_ERROR: str | None = None
try:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec, rsa
    from cryptography.hazmat.primitives.asymmetric.utils import (
        decode_dss_signature,
        encode_dss_signature,
    )
    from cryptography.x509.oid import NameOID
except ImportError as exc:  # Keep --help and --selftest failure output actionable.
    CRYPTOGRAPHY_IMPORT_ERROR = str(exc)
    x509 = None  # type: ignore[assignment]
    hashes = None  # type: ignore[assignment]
    serialization = None  # type: ignore[assignment]
    ec = None  # type: ignore[assignment]
    rsa = None  # type: ignore[assignment]
    decode_dss_signature = None  # type: ignore[assignment]
    encode_dss_signature = None  # type: ignore[assignment]
    NameOID = None  # type: ignore[assignment]


API_BASE = "https://api.appstoreconnect.apple.com"
DEFAULT_TIMEOUT_SECONDS = 60.0
JWT_LIFETIME_SECONDS = 1_200
MAX_HTTP_ATTEMPTS = 3
PROJECT_YML = Path("/Users/jt/Code/AppDev/project.yml")
CONFIG_PATH = Path.home() / ".appstoreconnect" / "config.json"
PRIVATE_KEYS_DIR = Path.home() / ".appstoreconnect" / "private_keys"

# App Store names knowingly registered as throwaways so an app record could exist before the
# naming/trademark workstream closed. `audit` re-raises these on every run — see the blocker
# built in command_audit(). Add a name here the moment you register another placeholder.
PLACEHOLDER_APP_NAMES = frozenset(
    {
        "harrys playhouse",
        "harrys playhouse garage",
    }
)


def normalized_placeholder_name(name: str) -> str:
    """Fold case, curly/straight apostrophes and spacing so "Harry's Playhouse" matches."""

    lowered = name.strip().lower().replace("’", "'").replace("'", "")
    return " ".join(lowered.split())

JsonValue = dict[str, Any] | list[Any] | str | int | float | bool | None


class ASCError(RuntimeError):
    """An App Store Connect HTTP failure with parsed error details."""

    def __init__(
        self,
        status: int | None,
        errors: list[dict[str, str]],
        fallback: str,
    ) -> None:
        self.status = status
        self.errors = errors
        self.fallback = fallback
        super().__init__(self.user_message())

    def user_message(self) -> str:
        lines: list[str] = []
        if self.status == 401:
            lines.append(
                "auth failed: check Key ID / Issuer ID / key file / system clock"
            )
        for error in self.errors:
            parts = [
                value
                for value in (
                    error.get("status"),
                    error.get("code"),
                    error.get("title"),
                    error.get("detail"),
                )
                if value
            ]
            if parts:
                lines.append(" | ".join(parts))
        if not lines:
            lines.append(self.fallback)
        return "\n".join(lines)


class InputError(RuntimeError):
    """A locally detected, actionable command input failure."""


def require_cryptography() -> None:
    """Fail cleanly if this interpreter lacks the one permitted dependency."""

    if CRYPTOGRAPHY_IMPORT_ERROR:
        raise InputError(
            "cryptography is required by asc.py but is unavailable in this Python "
            f"interpreter: {CRYPTOGRAPHY_IMPORT_ERROR}. Install cryptography 43.0.3 "
            "for the interpreter used to invoke this script."
        )


@dataclass(frozen=True)
class Credentials:
    """Resolved App Store Connect credentials; values are never rendered."""

    key_id: str
    issuer_id: str
    key_path: Path


@dataclass(frozen=True)
class CommandResult:
    """A command's machine-readable result and requested process exit status."""

    payload: dict[str, Any]
    exit_code: int = 0


def b64url_encode(value: bytes) -> str:
    """Return unpadded Base64 URL encoding, as required by compact JWTs."""

    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def b64url_decode(value: str) -> bytes:
    """Decode unpadded Base64 URL text for offline validation only."""

    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)


def compact_json_bytes(value: Mapping[str, Any]) -> bytes:
    """Encode a JWT member deterministically without whitespace."""

    return json.dumps(value, separators=(",", ":"), sort_keys=True).encode("utf-8")


def build_jwt(
    private_key: ec.EllipticCurvePrivateKey,
    key_id: str,
    issuer_id: str,
    *,
    now: int | None = None,
    scopes: Sequence[str] | None = None,
) -> str:
    """Build an App Store Connect ES256 JWT with a JOSE-format signature.

    ``scope`` is deliberately omitted unless the caller passed one or more
    explicit ``--scope`` values.  Team-scoped keys otherwise must not receive
    a scope claim.
    """

    require_cryptography()
    if private_key.curve.name != "secp256r1":
        raise InputError("the App Store Connect private key must use P-256 (secp256r1)")
    if not key_id.strip() or not issuer_id.strip():
        raise InputError("Key ID and Issuer ID must both be non-empty")

    issued_at = int(time.time()) if now is None else int(now)
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload: dict[str, Any] = {
        "iss": issuer_id,
        "iat": issued_at,
        "exp": issued_at + JWT_LIFETIME_SECONDS,
        "aud": "appstoreconnect-v1",
    }
    if scopes:
        payload["scope"] = list(scopes)

    signing_input = (
        f"{b64url_encode(compact_json_bytes(header))}."
        f"{b64url_encode(compact_json_bytes(payload))}"
    ).encode("ascii")
    der_signature = private_key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r_value, s_value = decode_dss_signature(der_signature)
    jose_signature = r_value.to_bytes(32, "big") + s_value.to_bytes(32, "big")
    if len(jose_signature) != 64:
        raise InputError("unexpected ES256 signature length")
    return f"{signing_input.decode('ascii')}.{b64url_encode(jose_signature)}"


def parse_config(path: Path) -> dict[str, str]:
    """Read a small credentials config without exposing its values in errors."""

    if not path.is_file():
        return {}
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise InputError(f"cannot read credentials config {path}: {exc}") from exc
    if not isinstance(raw, dict):
        raise InputError(f"credentials config {path} must contain a JSON object")

    result: dict[str, str] = {}
    for field in ("key_id", "issuer_id", "key_path"):
        value = raw.get(field)
        if value is not None and not isinstance(value, str):
            raise InputError(f"credentials config {path} field {field!r} must be a string")
        if isinstance(value, str) and value.strip():
            result[field] = value.strip()
    return result


def credential_missing_message() -> str:
    """Give an exact, safe recovery path when discovery cannot resolve a key."""

    return (
        "missing App Store Connect credentials. Need both Key ID and Issuer ID, plus "
        "the .p8 key path. Supply --key-id KEY_ID --issuer-id ISSUER_ID "
        "--key-path /path/AuthKey_KEY_ID.p8; or set ASC_KEY_ID, ASC_ISSUER_ID, "
        "ASC_KEY_PATH; or create "
        f"{CONFIG_PATH} containing {{\"key_id\":...,\"issuer_id\":...,\"key_path\":...}}. "
        f"If exactly one {PRIVATE_KEYS_DIR}/AuthKey_*.p8 exists, it is auto-discovered "
        "only when the Issuer ID is already known."
    )


def resolve_credentials(args: argparse.Namespace) -> Credentials:
    """Resolve credentials in the mandated flags/env/config/autodiscovery order."""

    config = parse_config(CONFIG_PATH)

    def argument_value(name: str) -> str | None:
        value = getattr(args, name, None)
        return value.strip() if isinstance(value, str) and value.strip() else None

    key_id = argument_value("key_id") or os.environ.get("ASC_KEY_ID") or config.get("key_id")
    issuer_id = (
        argument_value("issuer_id")
        or os.environ.get("ASC_ISSUER_ID")
        or config.get("issuer_id")
    )
    raw_key_path = (
        argument_value("key_path")
        or os.environ.get("ASC_KEY_PATH")
        or config.get("key_path")
    )

    key_path: Path | None = None
    if raw_key_path:
        configured_path = Path(raw_key_path).expanduser()
        if not configured_path.is_absolute() and config.get("key_path") == raw_key_path:
            configured_path = CONFIG_PATH.parent / configured_path
        key_path = configured_path
    else:
        candidates = sorted(PRIVATE_KEYS_DIR.glob("AuthKey_*.p8"))
        if len(candidates) == 1 and issuer_id:
            key_path = candidates[0]
            match = re.fullmatch(r"AuthKey_(.+)\.p8", key_path.name)
            discovered_key_id = match.group(1) if match else None
            if key_id and discovered_key_id and key_id != discovered_key_id:
                raise InputError(
                    "the supplied Key ID does not match the one derivable from the only "
                    f"auto-discovered key file {key_path}; specify the intended --key-path "
                    "explicitly or correct the Key ID"
                )
            if not key_id:
                key_id = discovered_key_id

    if not key_id or not issuer_id or key_path is None:
        raise InputError(credential_missing_message())
    if not key_path.is_file():
        raise InputError(
            f"App Store Connect key file does not exist or is not a file: {key_path}. "
            "Provide the correct --key-path (or ASC_KEY_PATH/config key_path)."
        )
    return Credentials(key_id=key_id, issuer_id=issuer_id, key_path=key_path)


def load_private_key(credentials: Credentials) -> ec.EllipticCurvePrivateKey:
    """Load the PEM private key without ever serializing or displaying it."""

    try:
        loaded = serialization.load_pem_private_key(
            credentials.key_path.read_bytes(), password=None
        )
    except (OSError, ValueError, TypeError) as exc:
        raise InputError(
            f"cannot load App Store Connect private key at {credentials.key_path}: {exc}"
        ) from exc
    if not isinstance(loaded, ec.EllipticCurvePrivateKey):
        raise InputError("App Store Connect private key is not an EC P-256 private key")
    if loaded.curve.name != "secp256r1":
        raise InputError("App Store Connect private key must use P-256 (secp256r1)")
    return loaded


def parse_asc_errors(raw: bytes, status: int | None) -> list[dict[str, str]]:
    """Extract the documented ASC error envelope without exposing request data."""

    try:
        body = json.loads(raw.decode("utf-8")) if raw else {}
    except (UnicodeDecodeError, json.JSONDecodeError):
        return []
    if not isinstance(body, dict):
        return []
    candidate_errors = body.get("errors")
    if not isinstance(candidate_errors, list):
        return []
    errors: list[dict[str, str]] = []
    for candidate in candidate_errors:
        if not isinstance(candidate, dict):
            continue
        error: dict[str, str] = {}
        for field in ("status", "code", "title", "detail"):
            value = candidate.get(field)
            if value is not None:
                error[field] = str(value)
        if status is not None and "status" not in error:
            error["status"] = str(status)
        errors.append(error)
    return errors


def retry_delay(headers: Mapping[str, str] | None, attempt_number: int) -> float:
    """Use Retry-After when valid; otherwise use a short exponential backoff."""

    retry_after = headers.get("Retry-After") if headers else None
    if retry_after:
        try:
            return max(0.0, float(retry_after))
        except ValueError:
            pass
    return float(2 ** (attempt_number - 1))


class AppStoreConnectClient:
    """Minimal urllib client with ASC errors, pagination, and safe retries."""

    def __init__(
        self,
        credentials: Credentials,
        *,
        timeout_seconds: float,
        scopes: Sequence[str] | None,
    ) -> None:
        self.credentials = credentials
        self.private_key = load_private_key(credentials)
        self.timeout_seconds = timeout_seconds
        self.scopes = tuple(scopes or ())

    def _url(self, path_or_url: str, params: Mapping[str, Any] | None) -> str:
        url = path_or_url if path_or_url.startswith("https://") else urljoin(API_BASE, path_or_url)
        if params:
            query = urlencode(params, doseq=True)
            separator = "&" if "?" in url else "?"
            url = f"{url}{separator}{query}"
        return url

    def request(
        self,
        method: str,
        path_or_url: str,
        *,
        params: Mapping[str, Any] | None = None,
        body: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Send one JSON request, retrying only ASC rate/server failures."""

        url = self._url(path_or_url, params)
        encoded_body = (
            json.dumps(body, separators=(",", ":")).encode("utf-8")
            if body is not None
            else None
        )
        for attempt in range(1, MAX_HTTP_ATTEMPTS + 1):
            token = build_jwt(
                self.private_key,
                self.credentials.key_id,
                self.credentials.issuer_id,
                scopes=self.scopes,
            )
            headers = {
                "Accept": "application/json",
                "Authorization": f"Bearer {token}",
                "User-Agent": "Garage-ASC-CLI/1.0",
            }
            if encoded_body is not None:
                headers["Content-Type"] = "application/json"
            request = Request(url, data=encoded_body, headers=headers, method=method)
            try:
                with urlopen(request, timeout=self.timeout_seconds) as response:
                    payload = response.read()
                    if not payload:
                        return {}
                    decoded = json.loads(payload.decode("utf-8"))
                    if not isinstance(decoded, dict):
                        raise ASCError(
                            response.status,
                            [],
                            "App Store Connect returned a non-object JSON response",
                        )
                    return decoded
            except HTTPError as exc:
                error_body = exc.read()
                if exc.code in (429,) or 500 <= exc.code <= 599:
                    if attempt < MAX_HTTP_ATTEMPTS:
                        time.sleep(retry_delay(exc.headers, attempt))
                        continue
                raise ASCError(
                    exc.code,
                    parse_asc_errors(error_body, exc.code),
                    f"App Store Connect request failed with HTTP {exc.code}",
                ) from exc
            except URLError as exc:
                raise ASCError(None, [], f"network error contacting App Store Connect: {exc.reason}") from exc
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise ASCError(None, [], f"invalid JSON returned by App Store Connect: {exc}") from exc
        raise ASCError(None, [], "App Store Connect request exhausted retries")

    def get(
        self, path_or_url: str, params: Mapping[str, Any] | None = None
    ) -> dict[str, Any]:
        return self.request("GET", path_or_url, params=params)

    def post(self, path: str, body: Mapping[str, Any]) -> dict[str, Any]:
        return self.request("POST", path, body=body)

    def patch(self, path: str, body: Mapping[str, Any]) -> dict[str, Any]:
        return self.request("PATCH", path, body=body)

    def delete(self, path: str) -> dict[str, Any]:
        return self.request("DELETE", path)

    def get_paginated(
        self, path: str, params: Mapping[str, Any] | None = None
    ) -> dict[str, list[dict[str, Any]]]:
        """Follow ``links.next``, retaining all data and de-duplicated includes."""

        next_url: str | None = path
        next_params: Mapping[str, Any] | None = params
        data: list[dict[str, Any]] = []
        included: list[dict[str, Any]] = []
        seen_included: set[tuple[str, str]] = set()
        while next_url:
            page = self.get(next_url, next_params)
            page_data = page.get("data", [])
            if isinstance(page_data, list):
                data.extend(item for item in page_data if isinstance(item, dict))
            elif isinstance(page_data, dict):
                data.append(page_data)
            page_included = page.get("included", [])
            if isinstance(page_included, list):
                for item in page_included:
                    if not isinstance(item, dict):
                        continue
                    key = (str(item.get("type", "")), str(item.get("id", "")))
                    if key not in seen_included:
                        included.append(item)
                        seen_included.add(key)
            links = page.get("links")
            next_candidate = links.get("next") if isinstance(links, dict) else None
            next_url = next_candidate if isinstance(next_candidate, str) and next_candidate else None
            next_params = None
        return {"data": data, "included": included}


def resource_attributes(resource: Mapping[str, Any]) -> dict[str, Any]:
    """Return a resource attributes object or an empty dictionary."""

    attributes = resource.get("attributes")
    return dict(attributes) if isinstance(attributes, dict) else {}


def included_index(included: Iterable[Mapping[str, Any]]) -> dict[tuple[str, str], dict[str, Any]]:
    """Index JSON:API included resources by (type, id)."""

    result: dict[tuple[str, str], dict[str, Any]] = {}
    for resource in included:
        resource_type = resource.get("type")
        resource_id = resource.get("id")
        if isinstance(resource_type, str) and isinstance(resource_id, str):
            result[(resource_type, resource_id)] = dict(resource)
    return result


def relationship_data(resource: Mapping[str, Any], name: str) -> dict[str, Any] | None:
    """Return a to-one relationship resource identifier, if provided."""

    relationships = resource.get("relationships")
    if not isinstance(relationships, dict):
        return None
    relationship = relationships.get(name)
    if not isinstance(relationship, dict):
        return None
    data = relationship.get("data")
    return dict(data) if isinstance(data, dict) else None


def resource_summary(resource: Mapping[str, Any], *fields: str) -> dict[str, Any]:
    """Make a deliberately small, secret-safe resource summary."""

    attributes = resource_attributes(resource)
    summary: dict[str, Any] = {"id": resource.get("id"), "type": resource.get("type")}
    for field in fields:
        summary[field] = attributes.get(field)
    return summary


def parse_iso8601(value: Any) -> datetime | None:
    """Parse ASC's ISO-8601 timestamp into an aware UTC datetime."""

    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def is_expired(value: Any, *, now: datetime | None = None) -> bool:
    """Treat a missing/unparseable date as not proven expired, not as active."""

    parsed = parse_iso8601(value)
    if parsed is None:
        return False
    return parsed <= (now or datetime.now(UTC))


def expiration_status(value: Any, *, now: datetime | None = None) -> str:
    """Return unexpired, expired, or unknown without treating unknown as safe."""

    parsed = parse_iso8601(value)
    if parsed is None:
        return "unknown"
    return "expired" if parsed <= (now or datetime.now(UTC)) else "unexpired"


def release_bundle_id_from_project(path: Path = PROJECT_YML) -> str:
    """Read the Garage target's explicit Release bundle identifier from project.yml.

    A general YAML loader is intentionally avoided to keep this release tool
    dependency-light.  The parser only accepts the known XcodeGen nesting:
    ``targets -> Garage -> settings -> configs -> Release``.
    """

    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise InputError(f"cannot read project.yml at {path}: {exc}") from exc

    target_indent: int | None = None
    settings_indent: int | None = None
    configs_indent: int | None = None
    release_indent: int | None = None
    in_targets = False

    for original_line in lines:
        if not original_line.strip() or original_line.lstrip().startswith("#"):
            continue
        indent = len(original_line) - len(original_line.lstrip(" "))
        stripped = original_line.strip()
        if stripped == "targets:" and indent == 0:
            in_targets = True
            continue
        if not in_targets:
            continue
        if target_indent is None:
            if stripped == "Garage:" and indent > 0:
                target_indent = indent
            continue
        if indent <= target_indent:
            break
        if settings_indent is None:
            if stripped == "settings:" and indent > target_indent:
                settings_indent = indent
            continue
        if indent <= settings_indent:
            settings_indent = None
            configs_indent = None
            release_indent = None
            continue
        if configs_indent is None:
            if stripped == "configs:" and indent > settings_indent:
                configs_indent = indent
            continue
        if indent <= configs_indent:
            configs_indent = None
            release_indent = None
            continue
        if release_indent is None:
            if stripped == "Release:" and indent > configs_indent:
                release_indent = indent
            continue
        if indent <= release_indent:
            release_indent = None
            continue
        match = re.match(
            r"^PRODUCT_BUNDLE_IDENTIFIER:\s*(?P<value>[^#]+?)\s*$", stripped
        )
        if match:
            value = match.group("value").strip().strip("\"'")
            if value:
                return value

    raise InputError(
        f"could not find Garage settings.configs.Release.PRODUCT_BUNDLE_IDENTIFIER in {path}"
    )


def make_client(args: argparse.Namespace) -> AppStoreConnectClient:
    """Resolve credentials only for a command that actually contacts ASC."""

    require_cryptography()
    timeout = float(getattr(args, "timeout", DEFAULT_TIMEOUT_SECONDS))
    if timeout <= 0:
        raise InputError("--timeout must be greater than zero")
    scopes = getattr(args, "scope", None)
    return AppStoreConnectClient(
        resolve_credentials(args), timeout_seconds=timeout, scopes=scopes
    )


def list_apps(client: AppStoreConnectClient) -> list[dict[str, Any]]:
    """List all app records using the canonical ASC summary fields."""

    response = client.get_paginated("/v1/apps", {"limit": 200})
    return [
        resource_summary(
            resource,
            "name",
            "bundleId",
            "sku",
            "primaryLocale",
            "contentRightsDeclaration",
        )
        for resource in response["data"]
    ]


def find_app_by_bundle_id(client: AppStoreConnectClient, bundle_id: str) -> dict[str, Any]:
    """Find exactly one ASC app record for a bundle identifier."""

    response = client.get_paginated(
        "/v1/apps", {"filter[bundleId]": bundle_id, "limit": 200}
    )
    matches = [
        resource
        for resource in response["data"]
        if resource_attributes(resource).get("bundleId") == bundle_id
    ]
    if not matches:
        raise InputError(f"no App Store Connect app record exists for bundle ID {bundle_id!r}")
    if len(matches) > 1:
        raise InputError(f"multiple App Store Connect app records match bundle ID {bundle_id!r}")
    return matches[0]


def get_app(client: AppStoreConnectClient, args: argparse.Namespace) -> dict[str, Any]:
    """Resolve an app from exactly one of the supported identifiers."""

    if getattr(args, "bundle_id", None):
        return find_app_by_bundle_id(client, args.bundle_id)
    if getattr(args, "app_id", None):
        response = client.get(f"/v1/apps/{args.app_id}")
        data = response.get("data")
        if not isinstance(data, dict):
            raise ASCError(None, [], "App Store Connect returned no app data")
        return data
    raise InputError("pass exactly one of --bundle-id or --app-id")


def optional_get(client: AppStoreConnectClient, path: str) -> dict[str, Any] | None:
    """Read an optional singleton relationship while preserving real failures."""

    try:
        response = client.get(path)
    except ASCError as exc:
        if exc.status == 404:
            return None
        raise
    data = response.get("data")
    return data if isinstance(data, dict) else None


def app_info_summary(
    resource: Mapping[str, Any], included: Mapping[tuple[str, str], Mapping[str, Any]]
) -> dict[str, Any]:
    """Summarize app-info categories and age declaration from JSON:API includes."""

    attributes = resource_attributes(resource)
    result: dict[str, Any] = {
        "id": resource.get("id"),
        "appStoreState": attributes.get("appStoreState"),
        "state": attributes.get("state"),
        "name": attributes.get("name"),
    }
    for relationship_name in ("primaryCategory", "secondaryCategory", "ageRatingDeclaration"):
        related = relationship_data(resource, relationship_name)
        if related is None:
            result[relationship_name] = None
            continue
        key = (str(related.get("type", "")), str(related.get("id", "")))
        resolved = included.get(key)
        if resolved is None:
            result[relationship_name] = {
                "id": related.get("id"),
                "type": related.get("type"),
            }
            continue
        related_attributes = resource_attributes(resolved)
        result[relationship_name] = {
            "id": resolved.get("id"),
            "type": resolved.get("type"),
            **related_attributes,
        }
    return result


def beta_review_summary(resource: Mapping[str, Any] | None) -> dict[str, Any] | None:
    """Return beta-review state while deliberately excluding demo passwords."""

    if resource is None:
        return None
    attributes = resource_attributes(resource)
    return {
        "id": resource.get("id"),
        "contactFirstName": attributes.get("contactFirstName"),
        "contactLastName": attributes.get("contactLastName"),
        "contactEmail": attributes.get("contactEmail"),
        "contactPhone": attributes.get("contactPhone"),
        "demoAccountName": attributes.get("demoAccountName"),
        "demoAccountRequired": attributes.get("demoAccountRequired"),
        "demoAccountPasswordConfigured": bool(attributes.get("demoAccountPassword")),
        "notesConfigured": bool(attributes.get("notes")),
    }


def collect_app_details(client: AppStoreConnectClient, app: Mapping[str, Any]) -> dict[str, Any]:
    """Fetch the app's requested metadata, build, and TestFlight surfaces."""

    app_id = str(app.get("id", ""))
    if not app_id:
        raise ASCError(None, [], "App Store Connect app resource has no id")
    app_infos_response = client.get_paginated(
        f"/v1/apps/{app_id}/appInfos",
        {"limit": 200, "include": "primaryCategory,secondaryCategory,ageRatingDeclaration"},
    )
    app_info_included = included_index(app_infos_response["included"])
    app_infos = [
        app_info_summary(resource, app_info_included)
        for resource in app_infos_response["data"]
    ]

    versions_response = client.get_paginated(
        f"/v1/apps/{app_id}/appStoreVersions", {"limit": 200}
    )
    versions = [
        resource_summary(resource, "versionString", "appStoreState", "platform")
        for resource in versions_response["data"]
    ]
    version_localizations: list[dict[str, Any]] = []
    for version_resource in versions_response["data"]:
        version_id = version_resource.get("id")
        if not isinstance(version_id, str):
            continue
        localizations_response = client.get_paginated(
            f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
            {"limit": 200},
        )
        for localization in localizations_response["data"]:
            localization_summary = resource_summary(
                localization,
                "locale",
                "description",
                "keywords",
                "marketingUrl",
                "promotionalText",
                "supportUrl",
                "whatsNew",
            )
            localization_summary["appStoreVersionId"] = version_id
            version_localizations.append(localization_summary)

    builds_response = client.get_paginated(f"/v1/apps/{app_id}/builds", {"limit": 200})
    beta_groups_response = client.get_paginated(
        f"/v1/apps/{app_id}/betaGroups", {"limit": 200}
    )
    beta_localizations_response = client.get_paginated(
        f"/v1/apps/{app_id}/betaAppLocalizations", {"limit": 200}
    )
    beta_review = optional_get(client, f"/v1/apps/{app_id}/betaAppReviewDetail")

    return {
        "app": resource_summary(
            app,
            "name",
            "bundleId",
            "sku",
            "primaryLocale",
            "contentRightsDeclaration",
        ),
        "appInfos": app_infos,
        "appStoreVersions": versions,
        "builds": [
            resource_summary(
                resource, "version", "processingState", "expired", "uploadedDate"
            )
            for resource in builds_response["data"]
        ],
        "betaGroups": [
            resource_summary(
                resource,
                "name",
                "isInternalGroup",
                "publicLinkEnabled",
                "hasAccessToAllBuilds",
            )
            for resource in beta_groups_response["data"]
        ],
        "betaAppLocalizations": [
            resource_summary(
                resource,
                "locale",
                "feedbackEmail",
                "description",
                "marketingUrl",
                "privacyPolicyUrl",
            )
            for resource in beta_localizations_response["data"]
        ],
        "betaAppReviewDetail": beta_review_summary(beta_review),
        "appStoreVersionLocalizations": version_localizations,
    }


def list_bundle_ids(client: AppStoreConnectClient) -> list[dict[str, Any]]:
    """List the bundle IDs registered with the team."""

    response = client.get_paginated("/v1/bundleIds", {"limit": 200})
    return [resource_summary(resource, "identifier", "name", "platform", "seedId") for resource in response["data"]]


def list_certificates(client: AppStoreConnectClient) -> list[dict[str, Any]]:
    """List certificates, explicitly marking expired ones."""

    response = client.get_paginated("/v1/certificates", {"limit": 200})
    certificates: list[dict[str, Any]] = []
    for resource in response["data"]:
        entry = resource_summary(
            resource,
            "certificateType",
            "name",
            "expirationDate",
            "serialNumber",
        )
        entry["status"] = expiration_status(entry.get("expirationDate"))
        entry["expired"] = entry["status"] == "expired"
        certificates.append(entry)
    return certificates


def list_profiles(client: AppStoreConnectClient) -> list[dict[str, Any]]:
    """List profiles with their associated bundle IDs and validity warnings."""

    response = client.get_paginated(
        "/v1/profiles", {"limit": 200, "include": "bundleId"}
    )
    included = included_index(response["included"])
    profiles: list[dict[str, Any]] = []
    for resource in response["data"]:
        entry = resource_summary(
            resource, "name", "profileType", "profileState", "expirationDate"
        )
        related = relationship_data(resource, "bundleId")
        if related is not None:
            bundle = included.get((str(related.get("type", "")), str(related.get("id", ""))))
            entry["bundleId"] = {
                "id": related.get("id"),
                "identifier": resource_attributes(bundle).get("identifier") if bundle else None,
            }
        else:
            entry["bundleId"] = None
        expiry_status = expiration_status(entry.get("expirationDate"))
        expired = expiry_status == "expired"
        state = str(entry.get("profileState") or "").upper()
        invalid = bool(state and state != "ACTIVE")
        flags = [
            flag
            for flag, enabled in (
                ("expired", expired),
                ("expiration-unknown", expiry_status == "unknown"),
                ("invalid", invalid),
            )
            if enabled
        ]
        entry["expirationStatus"] = expiry_status
        entry["expired"] = expired
        entry["invalid"] = invalid
        entry["flags"] = flags
        profiles.append(entry)
    return profiles


def command_doctor(args: argparse.Namespace) -> CommandResult:
    client = make_client(args)
    response = client.get("/v1/apps", {"limit": 1})
    meta = response.get("meta")
    paging = meta.get("paging") if isinstance(meta, dict) else None
    count = paging.get("total") if isinstance(paging, dict) else None
    if not isinstance(count, int):
        data = response.get("data")
        count = len(data) if isinstance(data, list) else 0
    return CommandResult({"ok": True, "teamAppCount": count})


def command_apps(args: argparse.Namespace) -> CommandResult:
    return CommandResult({"apps": list_apps(make_client(args))})


def command_app(args: argparse.Namespace) -> CommandResult:
    client = make_client(args)
    return CommandResult(collect_app_details(client, get_app(client, args)))


def command_bundle_ids(args: argparse.Namespace) -> CommandResult:
    return CommandResult({"bundleIds": list_bundle_ids(make_client(args))})


CAPABILITY_TYPES = {
    "push": "PUSH_NOTIFICATIONS",
    "apple-signin": "APPLE_ID_AUTH",
    "in-app-purchase": "IN_APP_PURCHASE",
}


def command_create_bundle_id(args: argparse.Namespace) -> CommandResult:
    """Register a bundle ID and enable its capabilities. Idempotent.

    Contrary to what `audit` reports, this is NOT operator-only: Apple exposes
    POST /v1/bundleIds and POST /v1/bundleIdCapabilities. Only *app record* creation
    (POST /v1/apps) is absent from the API.
    """

    client = make_client(args)
    identifier = args.identifier
    existing = [
        item
        for item in client.get_paginated("/v1/bundleIds", {"limit": 200})["data"]
        if (item.get("attributes") or {}).get("identifier") == identifier
    ]

    if existing:
        bundle = existing[0]
        created = False
    else:
        if args.dry_run:
            return CommandResult(
                {
                    "dryRun": True,
                    "requests": [
                        {
                            "method": "POST",
                            "path": "/v1/bundleIds",
                            "body": {
                                "data": {
                                    "type": "bundleIds",
                                    "attributes": {
                                        "identifier": identifier,
                                        "name": args.name,
                                        "platform": "IOS",
                                    },
                                }
                            },
                        }
                    ],
                }
            )
        response = client.request(
            "POST",
            "/v1/bundleIds",
            body={
                "data": {
                    "type": "bundleIds",
                    "attributes": {
                        "identifier": identifier,
                        "name": args.name,
                        "platform": "IOS",
                    },
                }
            },
        )
        bundle = response["data"]
        created = True

    bundle_id_resource = str(bundle.get("id"))
    # NB: this relationship rejects a `limit` parameter (400 PARAMETER_ERROR.ILLEGAL),
    # unlike almost every other ASC collection — request it bare.
    enabled = {
        (item.get("attributes") or {}).get("capabilityType")
        for item in client.request(
            "GET", f"/v1/bundleIds/{bundle_id_resource}/bundleIdCapabilities"
        )["data"]
    }

    requested = [CAPABILITY_TYPES[key] for key in (args.capability or [])]
    added: list[str] = []
    skipped: list[str] = []
    for capability in requested:
        if capability in enabled:
            skipped.append(capability)
            continue
        if args.dry_run:
            added.append(capability)
            continue
        attributes: dict[str, Any] = {"capabilityType": capability}
        if capability == "APPLE_ID_AUTH":
            # Sign In with Apple is rejected without a configuration ("Please select at least
            # one configuration"). This is the API form of the web UI's Configure ->
            # "Enable as a primary App ID".
            attributes["settings"] = [
                {
                    "key": "APPLE_ID_AUTH_APP_CONSENT",
                    "options": [{"key": "PRIMARY_APP_CONSENT"}],
                }
            ]
        try:
            client.request(
                "POST",
                "/v1/bundleIdCapabilities",
                body={
                    "data": {
                        "type": "bundleIdCapabilities",
                        "attributes": attributes,
                        "relationships": {
                            "bundleId": {
                                "data": {"type": "bundleIds", "id": bundle_id_resource}
                            }
                        },
                    }
                },
            )
            added.append(capability)
        except ASCError as error:
            # Some capabilities (notably IN_APP_PURCHASE) are always-on and reject an
            # explicit enable. That is a no-op, not a failure.
            skipped.append(f"{capability} (rejected: {error})")

    return CommandResult(
        {
            "bundleId": {
                "id": bundle_id_resource,
                "identifier": identifier,
                "created": created,
            },
            "capabilitiesAdded": added,
            "capabilitiesAlreadyPresent": skipped,
        }
    )


def command_signing(args: argparse.Namespace) -> CommandResult:
    client = make_client(args)
    return CommandResult(
        {"certificates": list_certificates(client), "profiles": list_profiles(client)}
    )


def beta_localization_is_configured(localizations: Sequence[Mapping[str, Any]]) -> bool:
    """Require an en-US description to call TestFlight info materially set."""

    for localization in localizations:
        if localization.get("locale") == "en-US" and localization.get("description"):
            return True
    return False


def beta_review_is_configured(review: Mapping[str, Any] | None) -> bool:
    """Assess review metadata without examining or disclosing its password."""

    if review is None:
        return False
    return all(
        review.get(field)
        for field in ("contactFirstName", "contactLastName", "contactEmail", "contactPhone")
    )


def add_blocker(
    blockers: list[dict[str, Any]],
    *,
    title: str,
    who: str,
    next_action: str,
    blocking_internal_qa: bool,
    evidence: str,
) -> None:
    """Append a consistently structured, numbered audit blocker."""

    blockers.append(
        {
            "number": len(blockers) + 1,
            "title": title,
            "who": who,
            "nextAction": next_action,
            "blockingInternalQA": blocking_internal_qa,
            "evidence": evidence,
        }
    )


def command_audit(args: argparse.Namespace) -> CommandResult:
    """Produce the read-only, evidence-bearing internal-TestFlight readiness report."""

    client = make_client(args)
    project_bundle_id = release_bundle_id_from_project()
    apps = list_apps(client)
    matching_apps = [app for app in apps if app.get("bundleId") == project_bundle_id]
    bundle_ids = list_bundle_ids(client)
    matching_bundle_resources = [
        item for item in bundle_ids if item.get("identifier") == project_bundle_id
    ]
    certificates = list_certificates(client)
    profiles = list_profiles(client)
    active_distribution_certificates = [
        certificate
        for certificate in certificates
        if certificate.get("certificateType") == "IOS_DISTRIBUTION"
        and certificate.get("status") == "unexpired"
    ]
    bundle_resource_ids = {
        str(bundle.get("id")) for bundle in matching_bundle_resources if bundle.get("id")
    }
    active_app_store_profiles = [
        profile
        for profile in profiles
        if profile.get("profileType") == "IOS_APP_STORE"
        and profile.get("expirationStatus") == "unexpired"
        and not profile.get("invalid")
        and isinstance(profile.get("bundleId"), dict)
        and str(profile["bundleId"].get("id")) in bundle_resource_ids
    ]

    testflight: list[dict[str, Any]] = []
    for app in matching_apps:
        app_id = app.get("id")
        if not isinstance(app_id, str):
            continue
        groups = client.get_paginated(f"/v1/apps/{app_id}/betaGroups", {"limit": 200})[
            "data"
        ]
        builds = client.get_paginated(f"/v1/apps/{app_id}/builds", {"limit": 200})["data"]
        localizations = client.get_paginated(
            f"/v1/apps/{app_id}/betaAppLocalizations", {"limit": 200}
        )["data"]
        review = optional_get(client, f"/v1/apps/{app_id}/betaAppReviewDetail")
        group_summaries = [
            resource_summary(
                group,
                "name",
                "isInternalGroup",
                "publicLinkEnabled",
                "hasAccessToAllBuilds",
            )
            for group in groups
        ]
        build_summaries = [
            resource_summary(
                build, "version", "processingState", "expired", "uploadedDate"
            )
            for build in builds
        ]
        localization_summaries = [
            resource_summary(
                localization,
                "locale",
                "feedbackEmail",
                "description",
                "marketingUrl",
                "privacyPolicyUrl",
            )
            for localization in localizations
        ]
        testflight.append(
            {
                "appId": app_id,
                "bundleId": app.get("bundleId"),
                "internalBetaGroups": [
                    group for group in group_summaries if group.get("isInternalGroup") is True
                ],
                "builds": build_summaries,
                "betaAppLocalizations": localization_summaries,
                "betaAppLocalizationsConfigured": beta_localization_is_configured(
                    localization_summaries
                ),
                "betaAppReviewDetail": beta_review_summary(review),
                "betaAppReviewDetailConfigured": beta_review_is_configured(
                    beta_review_summary(review)
                ),
            }
        )

    blockers: list[dict[str, Any]] = []
    if not matching_apps:
        add_blocker(
            blockers,
            title="operator-only: app record creation",
            who="operator-only",
            next_action=(
                "Create the Garage app record in App Store Connect's web UI using "
                f"bundle ID {project_bundle_id}; Apple does not permit app-record creation via this API."
            ),
            blocking_internal_qa=True,
            evidence=f"No app record has bundleId {project_bundle_id!r}.",
        )
    if apps and not matching_apps:
        observed_bundle_ids = ", ".join(str(app.get("bundleId")) for app in apps)
        add_blocker(
            blockers,
            title="Release bundle ID does not match an App Store Connect app record",
            who="operator-only",
            next_action=(
                f"Either create/select an ASC app record for {project_bundle_id}, or approve a "
                "reviewed change to the protected Release PRODUCT_BUNDLE_IDENTIFIER."
            ),
            blocking_internal_qa=True,
            evidence=(
                f"project.yml Release is {project_bundle_id!r}; ASC app records are: "
                f"{observed_bundle_ids or '(none)'}"
            ),
        )
    if not matching_bundle_resources:
        add_blocker(
            blockers,
            title="Registered developer bundle ID is missing",
            who="agent",
            next_action=(
                f"Run: asc.py create-bundle-id --identifier {project_bundle_id} "
                f'--name "Garage vehicle service log" --capability push --capability apple-signin. '
                "Apple's API does support POST /v1/bundleIds — only app-record creation is web-UI only."
            ),
            blocking_internal_qa=True,
            evidence=f"No Bundle ID resource has identifier {project_bundle_id!r}.",
        )
    if not active_distribution_certificates:
        add_blocker(
            blockers,
            title="No unexpired iOS Distribution certificate",
            who="agent (with an ASC API key authorized for provisioning)",
            next_action=(
                "Generate a CSR/key with create-cert --generate-key and create an "
                "IOS_DISTRIBUTION certificate; retain the key in a secure signing system."
            ),
            blocking_internal_qa=True,
            evidence="No IOS_DISTRIBUTION certificate has a future expiration date.",
        )
    if matching_bundle_resources and not active_app_store_profiles:
        add_blocker(
            blockers,
            title="No active IOS_APP_STORE provisioning profile for the Release bundle ID",
            who="agent (with an ASC API key authorized for provisioning)",
            next_action=(
                "Run create-profile with the registered bundle ID and an unexpired "
                "IOS_DISTRIBUTION certificate ID, writing the profile to a new explicit path."
            ),
            blocking_internal_qa=True,
            evidence=(
                f"No active, unexpired IOS_APP_STORE profile is tied to {project_bundle_id!r}."
            ),
        )

    for record in testflight:
        if not record["internalBetaGroups"]:
            add_blocker(
                blockers,
                title="No internal TestFlight beta group",
                who="agent (with an ASC API key authorized for TestFlight)",
                next_action=(
                    f"Run testflight-setup --bundle-id {project_bundle_id} --group QA "
                    "and add the intended internal ASC users as beta testers."
                ),
                blocking_internal_qa=True,
                evidence=f"ASC app {record['appId']} has no beta group with isInternalGroup=true.",
            )
        if not record["builds"]:
            add_blocker(
                blockers,
                title="No uploaded build is available for TestFlight",
                who="operator-only",
                next_action=(
                    "Build a signed IPA on a signing-capable Mac or CI system, then use "
                    "upload --ipa PATH after placing the API .p8 in the standard altool directory."
                ),
                blocking_internal_qa=True,
                evidence=f"ASC app {record['appId']} reports zero builds.",
            )
        else:
            eligible_builds = [
                build
                for build in record["builds"]
                if build.get("processingState") == "VALID" and build.get("expired") is not True
            ]
            processing = [
                build
                for build in record["builds"]
                if build.get("processingState") not in {"VALID", "PROCESSING_FAILED"}
            ]
            failed = [
                build
                for build in record["builds"]
                if build.get("processingState") == "PROCESSING_FAILED"
            ]
            if processing:
                add_blocker(
                    blockers,
                    title="Uploaded build processing is not yet complete",
                    who="operator-only",
                    next_action=(
                        "Wait for Apple processing to reach VALID, or inspect and correct the "
                        "processing failure in App Store Connect before assigning the build to QA."
                    ),
                    blocking_internal_qa=True,
                    evidence=(
                        f"ASC app {record['appId']} build states: "
                        f"{', '.join(str(build.get('processingState')) for build in record['builds'])}"
                    ),
                )
            if failed and not processing:
                add_blocker(
                    blockers,
                    title="An uploaded build failed Apple processing",
                    who="operator-only",
                    next_action="Inspect the processing failure in App Store Connect, correct the IPA, and upload a new build.",
                    blocking_internal_qa=True,
                    evidence=f"ASC app {record['appId']} has PROCESSING_FAILED build(s).",
                )
            if not eligible_builds and not processing and not failed:
                add_blocker(
                    blockers,
                    title="No valid, unexpired build is available for internal QA",
                    who="operator-only",
                    next_action=(
                        "Upload a new signed IPA and wait for Apple processing to reach VALID; "
                        "the existing builds are expired or otherwise not eligible."
                    ),
                    blocking_internal_qa=True,
                    evidence=(
                        f"ASC app {record['appId']} has no build with processingState=VALID "
                        "and expired=false."
                    ),
                )
        if not record["betaAppLocalizationsConfigured"]:
            add_blocker(
                blockers,
                title="TestFlight beta app information is not materially configured",
                who="agent (with approved TestFlight metadata)",
                next_action=(
                    f"Run testflight-setup --bundle-id {project_bundle_id} --group QA "
                    "--description '...' and optionally provide feedback, marketing, and privacy URLs."
                ),
                blocking_internal_qa=False,
                evidence=(
                    "No en-US betaAppLocalization has a description; Apple requires one "
                    "before external beta review."
                ),
            )
        if not record["betaAppReviewDetailConfigured"]:
            add_blocker(
                blockers,
                title="Beta app review contact details are not configured",
                who="agent (if ASC exposes the existing review-detail resource)",
                next_action=(
                    "Run testflight-setup with all four contact fields. If the resource does not "
                    "exist, set it in App Store Connect's web UI; the API currently supports read/modify, not create."
                ),
                blocking_internal_qa=False,
                evidence=(
                    f"ASC app {record['appId']} has no complete betaAppReviewDetail; this is "
                    "required for external beta review, not internal QA."
                ),
            )

    # The App Store name was registered as a deliberate placeholder while the naming /
    # trademark workstream is still open (see docs/research/2026-07-24_underhood_trademark_
    # preclearance.md). A doc note is too easy to forget, so every audit re-raises it until
    # the record carries a real name. The name is freely editable until first public release.
    for app in matching_apps:
        app_name = str(app.get("name") or "")
        if normalized_placeholder_name(app_name) in PLACEHOLDER_APP_NAMES:
            add_blocker(
                blockers,
                title=f"App Store name is still the placeholder {app_name!r}",
                who="operator-only",
                next_action=(
                    "Set the real App Store name in App Store Connect before the first public "
                    "release (App Information -> Name). It is freely editable until then; after "
                    "a release it can only change with a new app version. The name must clear "
                    "trademark review first — the naming workstream is still open."
                ),
                blocking_internal_qa=False,
                evidence=(
                    f"ASC app {app.get('id')} is named {app_name!r}, which is on the known "
                    "placeholder list in scripts/release/asc.py."
                ),
            )

    add_blocker(
        blockers,
        title="operator-only: EU trader status (Business section)",
        who="operator-only",
        next_action=(
            "Confirm and complete the EU trader-status declaration in App Store Connect's "
            "Business section before a public EU release."
        ),
        blocking_internal_qa=False,
        evidence="Not exposed by the App Store Connect API; cannot be verified by this read-only audit.",
    )
    add_blocker(
        blockers,
        title="operator-only: agreements/tax/banking",
        who="operator-only",
        next_action=(
            "Accept the applicable agreements and complete tax and banking setup in App Store "
            "Connect before paid/public distribution."
        ),
        blocking_internal_qa=False,
        evidence="Not exposed by the App Store Connect API; cannot be verified by this read-only audit.",
    )

    internal_blockers = [blocker for blocker in blockers if blocker["blockingInternalQA"]]
    payload = {
        "project": {"releaseBundleId": project_bundle_id, "projectYml": str(PROJECT_YML)},
        "appRecords": apps,
        "matchingAppRecords": matching_apps,
        "bundleIdRegistration": matching_bundle_resources,
        "signing": {
            "distributionCertificates": active_distribution_certificates,
            "appStoreProfiles": active_app_store_profiles,
        },
        "testflight": testflight,
        "blockers": blockers,
        "internalQAReady": not internal_blockers,
        "internalQABlockerCount": len(internal_blockers),
    }
    return CommandResult(payload, exit_code=1 if args.strict and internal_blockers else 0)


def provided_beta_localization_attributes(args: argparse.Namespace) -> dict[str, Any]:
    """Build the exact metadata attributes the user supplied, without defaults."""

    values = {
        "feedbackEmail": getattr(args, "feedback_email", None),
        "description": getattr(args, "description", None),
        "marketingUrl": getattr(args, "marketing_url", None),
        "privacyPolicyUrl": getattr(args, "privacy_policy_url", None),
    }
    return {key: value for key, value in values.items() if value is not None}


def provided_beta_review_attributes(args: argparse.Namespace) -> dict[str, Any]:
    """Build beta review metadata from explicit flags only; no secret is rendered."""

    values = {
        "contactFirstName": getattr(args, "contact_first_name", None),
        "contactLastName": getattr(args, "contact_last_name", None),
        "contactEmail": getattr(args, "contact_email", None),
        "contactPhone": getattr(args, "contact_phone", None),
        "demoAccountName": getattr(args, "demo_account_name", None),
        "demoAccountPassword": getattr(args, "demo_account_password", None),
        "demoAccountRequired": getattr(args, "demo_account_required", None),
        "notes": getattr(args, "notes", None),
    }
    return {key: value for key, value in values.items() if value is not None}


def dry_run_testflight_setup(args: argparse.Namespace) -> CommandResult:
    """Describe all conditional requests without contacting ASC or loading a key."""

    localization_attributes = {"locale": "en-US", **provided_beta_localization_attributes(args)}
    review_attributes = provided_beta_review_attributes(args)
    app_id = "<resolved-app-id>"
    plan: list[dict[str, Any]] = [
        {
            "method": "GET",
            "path": f"/v1/apps?filter[bundleId]={args.bundle_id}&limit=200",
            "body": None,
            "purpose": "resolve the app record (not sent in dry-run)",
        },
        {
            "method": "GET",
            "path": f"/v1/apps/{app_id}/betaGroups?limit=200",
            "body": None,
            "purpose": "find an internal beta group named exactly as requested (not sent in dry-run)",
        },
        {
            "method": "POST",
            "path": "/v1/betaGroups",
            "body": {
                "data": {
                    "type": "betaGroups",
                    "attributes": {
                        "name": args.group,
                        "isInternalGroup": True,
                        "publicLinkEnabled": False,
                    },
                    "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                }
            },
            "purpose": "only if no matching internal group exists",
        },
        {
            "method": "GET",
            "path": f"/v1/apps/{app_id}/betaAppLocalizations?limit=200",
            "body": None,
            "purpose": "find an en-US beta localization (not sent in dry-run)",
        },
        {
            "method": "POST/PATCH",
            "path": "/v1/betaAppLocalizations or /v1/betaAppLocalizations/<existing-id>",
            "body": {
                "data": {
                    "type": "betaAppLocalizations",
                    "attributes": localization_attributes,
                    "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                }
            },
            "purpose": "create en-US or update only explicitly supplied metadata",
        },
        {
            "method": "GET",
            "path": f"/v1/apps/{app_id}/betaAppReviewDetail",
            "body": None,
            "purpose": "find the API-managed beta review-detail resource (not sent in dry-run)",
        },
    ]
    if review_attributes:
        plan.append(
            {
                "method": "PATCH",
                "path": "/v1/betaAppReviewDetails/<existing-id>",
                "body": {
                    "data": {
                        "type": "betaAppReviewDetails",
                        "id": "<existing-id>",
                        "attributes": review_attributes,
                    }
                },
                "purpose": "only if the review-detail resource exists; ASC provides no create endpoint",
            }
        )
    return CommandResult({"dryRun": True, "requests": plan})


def command_testflight_setup(args: argparse.Namespace) -> CommandResult:
    """Idempotently establish TestFlight metadata for one existing ASC app."""

    if args.dry_run:
        return dry_run_testflight_setup(args)

    client = make_client(args)
    app = find_app_by_bundle_id(client, args.bundle_id)
    app_id = str(app.get("id"))
    groups_response = client.get_paginated(f"/v1/apps/{app_id}/betaGroups", {"limit": 200})
    groups = groups_response["data"]
    same_name = [
        group
        for group in groups
        if resource_attributes(group).get("name") == args.group
    ]
    internal_matches = [
        group
        for group in same_name
        if resource_attributes(group).get("isInternalGroup") is True
    ]
    if same_name and not internal_matches:
        raise InputError(
            f"a beta group named {args.group!r} exists but is not internal; rename/remove it "
            "in App Store Connect before creating the required internal QA group"
        )
    actions: list[dict[str, Any]] = []
    if internal_matches:
        beta_group = internal_matches[0]
        actions.append(
            {
                "resource": "betaGroup",
                "action": "found",
                "id": beta_group.get("id"),
                "name": args.group,
            }
        )
        if resource_attributes(beta_group).get("publicLinkEnabled") is True:
            response = client.patch(
                f"/v1/betaGroups/{beta_group.get('id')}",
                {
                    "data": {
                        "type": "betaGroups",
                        "id": beta_group.get("id"),
                        "attributes": {"publicLinkEnabled": False},
                    }
                },
            )
            beta_group = response.get("data", beta_group)
            actions.append(
                {
                    "resource": "betaGroup",
                    "action": "updated",
                    "id": beta_group.get("id") if isinstance(beta_group, dict) else None,
                    "change": "publicLinkEnabled=false",
                }
            )
    else:
        response = client.post(
            "/v1/betaGroups",
            {
                "data": {
                    "type": "betaGroups",
                    "attributes": {
                        "name": args.group,
                        "isInternalGroup": True,
                        "publicLinkEnabled": False,
                    },
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": app_id}}
                    },
                }
            },
        )
        beta_group = response.get("data")
        actions.append(
            {
                "resource": "betaGroup",
                "action": "created",
                "id": beta_group.get("id") if isinstance(beta_group, dict) else None,
                "name": args.group,
            }
        )

    supplied_localization = provided_beta_localization_attributes(args)
    localizations_response = client.get_paginated(
        f"/v1/apps/{app_id}/betaAppLocalizations", {"limit": 200}
    )
    existing_localizations = [
        localization
        for localization in localizations_response["data"]
        if resource_attributes(localization).get("locale") == "en-US"
    ]
    if existing_localizations:
        localization = existing_localizations[0]
        if supplied_localization:
            response = client.patch(
                f"/v1/betaAppLocalizations/{localization.get('id')}",
                {
                    "data": {
                        "type": "betaAppLocalizations",
                        "id": localization.get("id"),
                        "attributes": supplied_localization,
                    }
                },
            )
            returned = response.get("data")
            actions.append(
                {
                    "resource": "betaAppLocalization",
                    "action": "updated",
                    "id": returned.get("id") if isinstance(returned, dict) else localization.get("id"),
                    "locale": "en-US",
                    "fields": sorted(supplied_localization),
                }
            )
        else:
            actions.append(
                {
                    "resource": "betaAppLocalization",
                    "action": "found",
                    "id": localization.get("id"),
                    "locale": "en-US",
                }
            )
    else:
        response = client.post(
            "/v1/betaAppLocalizations",
            {
                "data": {
                    "type": "betaAppLocalizations",
                    "attributes": {"locale": "en-US", **supplied_localization},
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": app_id}}
                    },
                }
            },
        )
        returned = response.get("data")
        actions.append(
            {
                "resource": "betaAppLocalization",
                "action": "created",
                "id": returned.get("id") if isinstance(returned, dict) else None,
                "locale": "en-US",
                "fields": ["locale", *sorted(supplied_localization)],
            }
        )

    supplied_review = provided_beta_review_attributes(args)
    review = optional_get(client, f"/v1/apps/{app_id}/betaAppReviewDetail")
    if review is None:
        actions.append(
            {
                "resource": "betaAppReviewDetail",
                "action": "not-created",
                "reason": "ASC API exposes read/modify endpoints but no create endpoint",
            }
        )
    elif supplied_review:
        response = client.patch(
            f"/v1/betaAppReviewDetails/{review.get('id')}",
            {
                "data": {
                    "type": "betaAppReviewDetails",
                    "id": review.get("id"),
                    "attributes": supplied_review,
                }
            },
        )
        returned = response.get("data")
        actions.append(
            {
                "resource": "betaAppReviewDetail",
                "action": "updated",
                "id": returned.get("id") if isinstance(returned, dict) else review.get("id"),
                "fields": sorted(supplied_review),
            }
        )
    else:
        actions.append(
            {
                "resource": "betaAppReviewDetail",
                "action": "found",
                "id": review.get("id"),
            }
        )
    return CommandResult(
        {
            "app": resource_summary(app, "name", "bundleId"),
            "group": args.group,
            "actions": actions,
        }
    )


def assert_new_output_path(path: Path, *, label: str) -> None:
    """Prevent a command from overwriting an existing signing artifact."""

    if path.exists():
        raise InputError(
            f"refusing to overwrite existing {label}: {path}. Choose a new output path."
        )
    if not path.parent.is_dir():
        raise InputError(f"output directory for {label} does not exist: {path.parent}")


def write_new_binary(path: Path, content: bytes, *, label: str, mode: int = 0o600) -> None:
    """Create a new private artifact with owner-only permissions and no overwrite."""

    assert_new_output_path(path, label=label)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(content)
        os.chmod(path, mode)
    except BaseException:
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass
        raise


def read_csr_pem(path: Path) -> str:
    """Validate a supplied PEM/DER CSR and return the PEM ASC expects."""

    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise InputError(f"cannot read CSR at {path}: {exc}") from exc
    try:
        if b"-----BEGIN" in raw:
            csr = x509.load_pem_x509_csr(raw)
        else:
            csr = x509.load_der_x509_csr(raw)
    except ValueError as exc:
        raise InputError(f"CSR at {path} is not valid PEM or DER: {exc}") from exc
    return csr.public_bytes(serialization.Encoding.PEM).decode("ascii")


def generated_distribution_csr() -> tuple[rsa.RSAPrivateKey, str]:
    """Generate the requested RSA-2048 key and PEM CSR entirely in memory."""

    private_key = rsa.generate_private_key(public_exponent=65_537, key_size=2_048)
    subject = x509.Name(
        [x509.NameAttribute(NameOID.COMMON_NAME, "Garage iOS Distribution")]
    )
    csr = x509.CertificateSigningRequestBuilder().subject_name(subject).sign(
        private_key, hashes.SHA256()
    )
    return private_key, csr.public_bytes(serialization.Encoding.PEM).decode("ascii")


def command_create_cert(args: argparse.Namespace) -> CommandResult:
    """Create an iOS distribution certificate and write only explicit new artifacts."""

    require_cryptography()
    output_path = Path(args.out).expanduser()
    assert_new_output_path(output_path, label="certificate output")
    generated_key: rsa.RSAPrivateKey | None = None
    generated_key_path: Path | None = None
    if args.generate_key:
        generated_key_path = Path(args.generate_key).expanduser()
        assert_new_output_path(generated_key_path, label="generated private key")
        generated_key, csr_content = generated_distribution_csr()
    else:
        csr_content = read_csr_pem(Path(args.csr).expanduser())

    client = make_client(args)
    response = client.post(
        "/v1/certificates",
        {
            "data": {
                "type": "certificates",
                "attributes": {"certificateType": args.type, "csrContent": csr_content},
            }
        },
    )
    certificate = response.get("data")
    if not isinstance(certificate, dict):
        raise ASCError(None, [], "App Store Connect returned no certificate data")
    certificate_content = resource_attributes(certificate).get("certificateContent")
    if not isinstance(certificate_content, str):
        raise ASCError(None, [], "App Store Connect returned no certificateContent")
    try:
        der_certificate = base64.b64decode(certificate_content, validate=True)
        x509.load_der_x509_certificate(der_certificate)
    except (ValueError, TypeError) as exc:
        raise ASCError(None, [], f"ASC certificateContent was not valid DER: {exc}") from exc

    if generated_key is not None and generated_key_path is not None:
        serialized_key = generated_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
        write_new_binary(generated_key_path, serialized_key, label="generated private key")
    write_new_binary(output_path, der_certificate, label="certificate output")
    return CommandResult(
        {
            "certificate": resource_summary(
                certificate, "certificateType", "name", "expirationDate", "serialNumber"
            ),
            "certificatePath": str(output_path),
            "generatedPrivateKeyPath": str(generated_key_path) if generated_key_path else None,
        }
    )


def find_bundle_id_resource(client: AppStoreConnectClient, identifier: str) -> dict[str, Any]:
    """Resolve a Developer Portal Bundle ID resource by exact identifier."""

    response = client.get_paginated(
        "/v1/bundleIds", {"filter[identifier]": identifier, "limit": 200}
    )
    matches = [
        resource
        for resource in response["data"]
        if resource_attributes(resource).get("identifier") == identifier
    ]
    if not matches:
        raise InputError(f"no registered Bundle ID exists for identifier {identifier!r}")
    if len(matches) > 1:
        raise InputError(f"multiple Bundle ID resources match identifier {identifier!r}")
    return matches[0]


def command_create_profile(args: argparse.Namespace) -> CommandResult:
    """Create a named App Store profile for a bundle ID and certificate."""

    output_path = Path(args.out).expanduser()
    assert_new_output_path(output_path, label="provisioning profile output")
    client = make_client(args)
    bundle_id = find_bundle_id_resource(client, args.bundle_id)
    response = client.post(
        "/v1/profiles",
        {
            "data": {
                "type": "profiles",
                "attributes": {"name": args.name, "profileType": args.type},
                "relationships": {
                    "bundleId": {
                        "data": {"type": "bundleIds", "id": bundle_id.get("id")}
                    },
                    "certificates": {
                        "data": [{"type": "certificates", "id": args.cert_id}]
                    },
                },
            }
        },
    )
    profile = response.get("data")
    if not isinstance(profile, dict):
        raise ASCError(None, [], "App Store Connect returned no provisioning profile data")
    profile_content = resource_attributes(profile).get("profileContent")
    if not isinstance(profile_content, str):
        raise ASCError(None, [], "App Store Connect returned no profileContent")
    try:
        decoded_profile = base64.b64decode(profile_content, validate=True)
    except (ValueError, TypeError) as exc:
        raise ASCError(None, [], f"ASC profileContent was not valid Base64: {exc}") from exc
    write_new_binary(output_path, decoded_profile, label="provisioning profile output")
    return CommandResult(
        {
            "profile": resource_summary(
                profile, "name", "profileType", "profileState", "expirationDate"
            ),
            "profilePath": str(output_path),
        }
    )


def command_upload(args: argparse.Namespace) -> CommandResult:
    """Upload or validate an IPA through Apple's requested altool command."""

    ipa_path = Path(args.ipa).expanduser()
    if not ipa_path.is_file():
        raise InputError(f"IPA does not exist or is not a file: {ipa_path}")
    credentials = resolve_credentials(args)
    expected_key_path = PRIVATE_KEYS_DIR / f"AuthKey_{credentials.key_id}.p8"
    if not expected_key_path.is_file():
        raise InputError(
            "altool reads the API key only from "
            f"{expected_key_path}; place the .p8 there with mode 0600 and retry."
        )
    action = "--validate-app" if args.validate else "--upload-app"
    command = [
        "xcrun",
        "altool",
        action,
        "-f",
        str(ipa_path),
        "-t",
        "ios",
        "--apiKey",
        credentials.key_id,
        "--apiIssuer",
        credentials.issuer_id,
    ]
    try:
        # `--json` is not guaranteed to be present on this subparser; match emit_result's
        # defensive read rather than assuming the flag was registered.
        if getattr(args, "json", False):
            completed = subprocess.run(command, check=False, text=True, capture_output=True)
            return CommandResult(
                {
                    "action": "validate" if args.validate else "upload",
                    "ipa": str(ipa_path),
                    "returnCode": completed.returncode,
                    "stdout": redact_text(completed.stdout),
                    "stderr": redact_text(completed.stderr),
                },
                exit_code=completed.returncode,
            )
        completed = subprocess.run(command, check=False)
    except FileNotFoundError as exc:
        raise InputError("xcrun/altool is not available on this machine") from exc
    return CommandResult(
        {
            "action": "validate" if args.validate else "upload",
            "ipa": str(ipa_path),
            "returnCode": completed.returncode,
        },
        exit_code=completed.returncode,
    )


SENSITIVE_FIELD_MARKERS = ("password", "private", "authorization", "jwt", "token", "csrcontent")


def redact_text(value: str) -> str:
    """Defensively remove PEM blocks from output captured from external tools."""

    return re.sub(
        r"-----BEGIN [^-]+-----.*?-----END [^-]+-----",
        "<redacted-pem>",
        value,
        flags=re.DOTALL,
    )


def redact_for_output(value: JsonValue, *, field_name: str = "") -> JsonValue:
    """Recursively redact secret-shaped values before any human or JSON rendering."""

    lowered_name = field_name.lower()
    if any(marker in lowered_name for marker in SENSITIVE_FIELD_MARKERS):
        return "<redacted>"
    if isinstance(value, dict):
        return {
            str(key): redact_for_output(item, field_name=str(key))
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [redact_for_output(item) for item in value]
    if isinstance(value, str):
        return redact_text(value)
    return value


def selftest_check(name: str, check: Callable[[], None], results: list[dict[str, Any]]) -> None:
    """Run an offline invariant and capture the result without leaking materials."""

    try:
        check()
    except Exception as exc:  # Self-test needs an individual PASS/FAIL receipt.
        results.append({"name": name, "passed": False, "detail": str(exc)})
    else:
        results.append({"name": name, "passed": True})


def command_selftest(args: argparse.Namespace) -> CommandResult:
    """Validate the auth conversion and project parser with no network or real key."""

    if CRYPTOGRAPHY_IMPORT_ERROR:
        return CommandResult(
            {
                "selftest": [
                    {
                        "name": "cryptography 43.0.3 is available to this interpreter",
                        "passed": False,
                        "detail": CRYPTOGRAPHY_IMPORT_ERROR,
                    }
                ],
                "passed": False,
            },
            exit_code=1,
        )
    private_key = ec.generate_private_key(ec.SECP256R1())
    fixed_now = 1_700_000_000
    key_id = "SELFTESTKEY"
    issuer_id = "00000000-1111-2222-3333-444444444444"
    token = build_jwt(private_key, key_id, issuer_id, now=fixed_now)
    header_segment, payload_segment, signature_segment = token.split(".")
    header = json.loads(b64url_decode(header_segment))
    payload = json.loads(b64url_decode(payload_segment))
    raw_signature = b64url_decode(signature_segment)
    results: list[dict[str, Any]] = []

    def require(condition: bool, message: str) -> None:
        if not condition:
            raise AssertionError(message)

    selftest_check(
        "JWT header decodes with ES256 and Key ID",
        lambda: require(
            header == {"alg": "ES256", "kid": key_id, "typ": "JWT"},
            "header is not the expected ES256 JWT header",
        ),
        results,
    )
    selftest_check(
        "JWT payload has correct issuer and audience",
        lambda: require(
            payload.get("iss") == issuer_id and payload.get("aud") == "appstoreconnect-v1",
            "issuer or audience is incorrect",
        ),
        results,
    )
    selftest_check(
        "JWT lifetime is exactly 1200 seconds",
        lambda: require(
            payload.get("exp") - payload.get("iat") == JWT_LIFETIME_SECONDS,
            "exp - iat is not 1200",
        ),
        results,
    )
    selftest_check(
        "JWT omits scope by default",
        lambda: require("scope" not in payload, "scope was included without --scope"),
        results,
    )
    selftest_check(
        "JWT signature is exactly 64-byte JOSE raw form",
        lambda: require(len(raw_signature) == 64, "signature length is not 64 bytes"),
        results,
    )

    def verify_signature() -> None:
        r_value = int.from_bytes(raw_signature[:32], "big")
        s_value = int.from_bytes(raw_signature[32:], "big")
        der_signature = encode_dss_signature(r_value, s_value)
        private_key.public_key().verify(
            der_signature,
            f"{header_segment}.{payload_segment}".encode("ascii"),
            ec.ECDSA(hashes.SHA256()),
        )

    selftest_check("JWT verifies with the ephemeral public key", verify_signature, results)
    selftest_check(
        "project.yml Release bundle ID is com.writes.harrysplayhouse",
        lambda: require(
            release_bundle_id_from_project() == "com.writes.harrysplayhouse",
            "unexpected Release PRODUCT_BUNDLE_IDENTIFIER",
        ),
        results,
    )
    passed = all(result["passed"] for result in results)
    return CommandResult({"selftest": results, "passed": passed}, exit_code=0 if passed else 1)


def add_common_options(parser: argparse.ArgumentParser) -> None:
    """Add options accepted both before and after each subcommand name."""

    parser.add_argument("--key-id", help="App Store Connect API Key ID")
    parser.add_argument("--issuer-id", help="App Store Connect API Issuer ID")
    parser.add_argument("--key-path", help="Path to the App Store Connect .p8 key")
    parser.add_argument(
        "--scope",
        action="append",
        help="Optional JWT scope claim; repeat for multiple scope entries (omitted by default)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=argparse.SUPPRESS,
        help=f"HTTP timeout in seconds (default: {int(DEFAULT_TIMEOUT_SECONDS)})",
    )
    parser.add_argument(
        "--json", action="store_true", default=argparse.SUPPRESS, help="emit machine-readable JSON"
    )


def make_common_parent() -> argparse.ArgumentParser:
    """Create an argparse parent whose defaults do not overwrite root values."""

    parent = argparse.ArgumentParser(add_help=False)
    add_common_options(parent)
    return parent


def build_parser() -> argparse.ArgumentParser:
    """Build the command-line interface and all release subcommands."""

    common = make_common_parent()
    parser = argparse.ArgumentParser(
        prog="asc.py",
        description="Garage App Store Connect/TestFlight and signing CLI",
        parents=[common],
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="run offline JWT and project.yml checks without credentials or network",
    )
    subparsers = parser.add_subparsers(dest="command", title="subcommands")

    subparsers.add_parser("doctor", help="verify ASC credentials", parents=[common])
    subparsers.add_parser("apps", help="list ASC app records", parents=[common])
    app_parser = subparsers.add_parser("app", help="deep read one ASC app", parents=[common])
    identifier_group = app_parser.add_mutually_exclusive_group(required=True)
    identifier_group.add_argument("--bundle-id")
    identifier_group.add_argument("--app-id")
    subparsers.add_parser("bundle-ids", help="list registered bundle IDs", parents=[common])
    new_bundle_parser = subparsers.add_parser(
        "create-bundle-id",
        help="register a bundle ID and enable capabilities (idempotent)",
        parents=[common],
    )
    new_bundle_parser.add_argument("--identifier", required=True)
    new_bundle_parser.add_argument("--name", required=True, help="portal display name, no @&*\"")
    new_bundle_parser.add_argument(
        "--capability",
        action="append",
        choices=sorted(CAPABILITY_TYPES),
        help="repeatable; e.g. --capability push --capability apple-signin",
    )
    new_bundle_parser.add_argument("--dry-run", action="store_true")
    subparsers.add_parser("signing", help="report certificates and profiles", parents=[common])
    audit_parser = subparsers.add_parser("audit", help="report internal-QA readiness", parents=[common])
    audit_parser.add_argument(
        "--strict",
        action="store_true",
        help="exit nonzero when an internal-QA blocker exists",
    )

    setup_parser = subparsers.add_parser(
        "testflight-setup", help="idempotently configure a QA TestFlight group", parents=[common]
    )
    setup_parser.add_argument("--bundle-id", required=True)
    setup_parser.add_argument("--group", required=True)
    setup_parser.add_argument("--feedback-email")
    setup_parser.add_argument("--description")
    setup_parser.add_argument("--marketing-url")
    setup_parser.add_argument("--privacy-policy-url")
    setup_parser.add_argument("--contact-first-name")
    setup_parser.add_argument("--contact-last-name")
    setup_parser.add_argument("--contact-email")
    setup_parser.add_argument("--contact-phone")
    setup_parser.add_argument("--demo-account-name")
    setup_parser.add_argument(
        "--demo-account-password",
        help="sent only to ASC; never printed or written by this tool",
    )
    demo_required = setup_parser.add_mutually_exclusive_group()
    demo_required.add_argument(
        "--demo-account-required", action="store_true", default=None
    )
    demo_required.add_argument(
        "--no-demo-account-required", action="store_false", dest="demo_account_required"
    )
    setup_parser.add_argument("--notes")
    setup_parser.add_argument("--dry-run", action="store_true")

    cert_parser = subparsers.add_parser(
        "create-cert", help="create an iOS Distribution certificate", parents=[common]
    )
    cert_parser.add_argument("--type", choices=["IOS_DISTRIBUTION"], required=True)
    csr_group = cert_parser.add_mutually_exclusive_group(required=True)
    csr_group.add_argument("--csr", help="existing PEM or DER certificate signing request")
    csr_group.add_argument(
        "--generate-key",
        metavar="OUT_KEY",
        help="create an RSA-2048 key at this new 0600 path and generate its CSR",
    )
    cert_parser.add_argument(
        "--out", required=True, help="new .cer output path for the returned DER certificate"
    )

    profile_parser = subparsers.add_parser(
        "create-profile", help="create an App Store provisioning profile", parents=[common]
    )
    profile_parser.add_argument("--name", required=True)
    profile_parser.add_argument("--bundle-id", required=True)
    profile_parser.add_argument("--cert-id", required=True)
    profile_parser.add_argument("--type", choices=["IOS_APP_STORE"], required=True)
    profile_parser.add_argument(
        "--out", required=True, help="new .mobileprovision output path"
    )

    upload_parser = subparsers.add_parser(
        "upload", help="upload or validate an IPA using xcrun altool", parents=[common]
    )
    upload_parser.add_argument("--ipa", required=True)
    upload_parser.add_argument("--validate", action="store_true")
    return parser


def render_human(command: str, payload: Mapping[str, Any]) -> None:
    """Render concise operator-facing output; JSON callers receive the full structure."""

    if command == "doctor":
        print(f"OK — credentials accepted; team app count: {payload['teamAppCount']}")
        return
    if command == "apps":
        apps = payload.get("apps", [])
        print(f"Apps ({len(apps)}):")
        for app in apps:
            print(
                f"- {app.get('id')} | {app.get('name')} | {app.get('bundleId')} | "
                f"sku={app.get('sku')} | locale={app.get('primaryLocale')} | "
                f"rights={app.get('contentRightsDeclaration')}"
            )
        return
    if command == "bundle-ids":
        bundle_ids = payload.get("bundleIds", [])
        print(f"Registered Bundle IDs ({len(bundle_ids)}):")
        for bundle_id in bundle_ids:
            print(
                f"- {bundle_id.get('id')} | {bundle_id.get('identifier')} | "
                f"{bundle_id.get('name')} | {bundle_id.get('platform')} | seed={bundle_id.get('seedId')}"
            )
        return
    if command == "signing":
        print("Certificates:")
        for certificate in payload.get("certificates", []):
            print(
                f"- {certificate.get('id')} | {certificate.get('certificateType')} | "
                f"{certificate.get('name')} | expires={certificate.get('expirationDate')} | "
                f"serial={certificate.get('serialNumber')} | {certificate.get('status')}"
            )
        print("Profiles:")
        for profile in payload.get("profiles", []):
            bundle = profile.get("bundleId") or {}
            flags = ", ".join(profile.get("flags", [])) or "valid"
            print(
                f"- {profile.get('id')} | {profile.get('name')} | {profile.get('profileType')} | "
                f"state={profile.get('profileState')} | expires={profile.get('expirationDate')} | "
                f"bundle={bundle.get('identifier') if isinstance(bundle, dict) else None} | {flags}"
            )
        return
    if command == "app":
        app = payload.get("app", {})
        print(f"App: {app.get('name')} ({app.get('bundleId')}) id={app.get('id')}")
        print("App infos:")
        for info in payload.get("appInfos", []):
            print(
                f"- {info.get('id')} | state={info.get('appStoreState') or info.get('state')} | "
                f"primary={info.get('primaryCategory')} | secondary={info.get('secondaryCategory')}"
            )
        print("App Store versions:")
        for version in payload.get("appStoreVersions", []):
            print(
                f"- {version.get('versionString')} | {version.get('platform')} | {version.get('appStoreState')}"
            )
        print("Builds:")
        for build in payload.get("builds", []):
            print(
                f"- {build.get('version')} | {build.get('processingState')} | "
                f"expired={build.get('expired')} | uploaded={build.get('uploadedDate')}"
            )
        print(f"Beta groups: {len(payload.get('betaGroups', []))}")
        print(f"Beta localizations: {len(payload.get('betaAppLocalizations', []))}")
        print(
            "Beta review detail: "
            f"{'configured resource found' if payload.get('betaAppReviewDetail') else 'not set'}"
        )
        print(
            f"App Store version localizations: {len(payload.get('appStoreVersionLocalizations', []))}"
        )
        return
    if command == "audit":
        project = payload.get("project", {})
        print("App Store Connect internal-TestFlight QA audit")
        print(f"Release bundle ID from project.yml: {project.get('releaseBundleId')}")
        print(f"ASC app records: {len(payload.get('appRecords', []))}")
        print(f"Matching app records: {len(payload.get('matchingAppRecords', []))}")
        signing = payload.get("signing", {})
        print(
            "Signing: "
            f"{len(signing.get('distributionCertificates', []))} unexpired distribution certificate(s), "
            f"{len(signing.get('appStoreProfiles', []))} active App Store profile(s)"
        )
        for testflight in payload.get("testflight", []):
            print(
                f"TestFlight app {testflight.get('appId')}: "
                f"internal groups={len(testflight.get('internalBetaGroups', []))}, "
                f"builds={len(testflight.get('builds', []))}, "
                f"beta info configured={testflight.get('betaAppLocalizationsConfigured')}, "
                f"beta review detail configured={testflight.get('betaAppReviewDetailConfigured')}"
            )
            for build in testflight.get("builds", []):
                print(
                    f"  build {build.get('version')}: {build.get('processingState')} "
                    f"(expired={build.get('expired')}, uploaded={build.get('uploadedDate')})"
                )
        blockers = payload.get("blockers", [])
        print(f"BLOCKERS ({len(blockers)}):")
        for blocker in blockers:
            scope = "internal QA blocker" if blocker.get("blockingInternalQA") else "public/external follow-up"
            print(
                f"{blocker.get('number')}. [{scope}] {blocker.get('title')} — "
                f"WHO: {blocker.get('who')} — NEXT: {blocker.get('nextAction')} "
                f"Evidence: {blocker.get('evidence')}"
            )
        verdict = "READY" if payload.get("internalQAReady") else "NOT READY"
        print(f"Internal QA verdict: {verdict}")
        return
    if command == "testflight-setup":
        if payload.get("dryRun"):
            print("DRY RUN — no credentials loaded and no requests sent:")
            for request in payload.get("requests", []):
                print(f"- {request.get('method')} {request.get('path')} ({request.get('purpose')})")
                if request.get("body") is not None:
                    print(json.dumps(request.get("body"), indent=2, sort_keys=True))
            return
        app = payload.get("app", {})
        print(f"TestFlight setup for {app.get('name')} ({app.get('bundleId')}):")
        for action in payload.get("actions", []):
            detail = action.get("fields") or action.get("change") or action.get("reason") or ""
            print(
                f"- {action.get('resource')}: {action.get('action')} "
                f"id={action.get('id')} {detail}"
            )
        return
    if command == "create-cert":
        certificate = payload.get("certificate", {})
        print(f"Created certificate {certificate.get('id')} ({certificate.get('certificateType')}).")
        print(f"DER certificate written: {payload.get('certificatePath')}")
        if payload.get("generatedPrivateKeyPath"):
            print(f"Generated private key written with mode 0600: {payload.get('generatedPrivateKeyPath')}")
        return
    if command == "create-profile":
        profile = payload.get("profile", {})
        print(f"Created profile {profile.get('id')} ({profile.get('profileType')}).")
        print(f"Decoded provisioning profile written: {payload.get('profilePath')}")
        return
    if command == "upload":
        print(
            f"altool {payload.get('action')} finished with exit code {payload.get('returnCode')} "
            f"for {payload.get('ipa')}"
        )
        return
    if command == "selftest":
        for result in payload.get("selftest", []):
            status = "PASS" if result.get("passed") else "FAIL"
            detail = f": {result['detail']}" if result.get("detail") else ""
            print(f"{status} — {result.get('name')}{detail}")
        print("SELFTEST PASS" if payload.get("passed") else "SELFTEST FAIL")
        return
    print(json.dumps(payload, indent=2, sort_keys=True))


def emit_result(command: str, args: argparse.Namespace, result: CommandResult) -> None:
    """Emit exactly one safe machine result or a concise human report."""

    safe_payload = redact_for_output(result.payload)
    if getattr(args, "json", False):
        print(json.dumps(safe_payload, indent=2, sort_keys=True))
    else:
        render_human(command, safe_payload if isinstance(safe_payload, dict) else {})


def emit_error(args: argparse.Namespace, exc: Exception) -> None:
    """Report failures without request headers, JWTs, private keys, or passwords."""

    message = redact_text(str(exc))
    if getattr(args, "json", False):
        print(json.dumps({"ok": False, "error": message}, sort_keys=True))
    else:
        print(f"ERROR: {message}", file=sys.stderr)


def main(argv: Sequence[str] | None = None) -> int:
    """Parse args, dispatch one command, and return a shell-friendly status."""

    parser = build_parser()
    args = parser.parse_args(argv)
    if args.selftest:
        command = "selftest"
        try:
            result = command_selftest(args)
        except (ASCError, InputError, OSError, ValueError) as exc:
            emit_error(args, exc)
            return 1
        emit_result(command, args, result)
        return result.exit_code
    if not args.command:
        parser.print_help(sys.stderr)
        return 2

    handlers: dict[str, Callable[[argparse.Namespace], CommandResult]] = {
        "doctor": command_doctor,
        "apps": command_apps,
        "app": command_app,
        "bundle-ids": command_bundle_ids,
        "signing": command_signing,
        "audit": command_audit,
        "testflight-setup": command_testflight_setup,
        "create-bundle-id": command_create_bundle_id,
        "create-cert": command_create_cert,
        "create-profile": command_create_profile,
        "upload": command_upload,
    }
    try:
        result = handlers[args.command](args)
    except (ASCError, InputError, OSError, ValueError) as exc:
        emit_error(args, exc)
        return 1 if args.command != "audit" else (1 if getattr(args, "strict", False) else 0)
    emit_result(args.command, args, result)
    return result.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
