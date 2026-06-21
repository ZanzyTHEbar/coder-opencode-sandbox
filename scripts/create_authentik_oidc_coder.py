#!/usr/bin/env python3
"""Create Authentik OIDC provider and application for Coder. Idempotent.
Run inside Authentik server container (pipe via docker exec)."""
import os
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "authentik.root.settings")
import django
django.setup()

from authentik.core.models import Application
from authentik.crypto.models import CertificateKeyPair
from authentik.flows.models import Flow
from authentik.providers.oauth2.models import OAuth2Provider, ScopeMapping


def required_env(name):
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"missing required environment variable: {name}")
    return value


CODER_ACCESS_URL = required_env("CODER_ACCESS_URL")
REDIRECT_URI = f"{CODER_ACCESS_URL}/api/v2/users/oidc/callback"
AUTHENTIK_PUBLIC_URL = required_env("AUTHENTIK_PUBLIC_URL")
APP_SLUG = os.environ.get("AUTHENTIK_CODER_APP_SLUG", "coder")
APP_NAME = os.environ.get("AUTHENTIK_CODER_APP_NAME", "Coder")

auth_flow = Flow.objects.get(slug="default-authentication-flow")
authz_flow = Flow.objects.get(slug="default-provider-authorization-implicit-consent")
inv_flow = Flow.objects.get(slug="default-provider-invalidation-flow")
signing_key = CertificateKeyPair.objects.get(name="authentik Self-signed Certificate")

provider, created = OAuth2Provider.objects.get_or_create(
    name="Coder OIDC",
    defaults={
        "authentication_flow": auth_flow,
        "authorization_flow": authz_flow,
        "invalidation_flow": inv_flow,
        "signing_key": signing_key,
        "encryption_key": None,
        "_redirect_uris": [{"matching_mode": "strict", "url": REDIRECT_URI}],
    },
)
if not created:
    provider.authentication_flow = auth_flow
    provider.authorization_flow = authz_flow
    provider.invalidation_flow = inv_flow
    provider.signing_key = signing_key
    provider.encryption_key = None
    provider._redirect_uris = [{"matching_mode": "strict", "url": REDIRECT_URI}]
    provider.save()

# Subject identifier: hashed so same user always gets same sub (avoids duplicate Coder users)
try:
    if hasattr(provider, "sub_mode"):
        provider.sub_mode = "hashed_user_id"
        provider.save(update_fields=["sub_mode"])
except Exception:
    pass

app, app_created = Application.objects.get_or_create(
    slug=APP_SLUG,
    defaults={"name": APP_NAME, "provider": provider, "meta_launch_url": CODER_ACCESS_URL},
)
if not app_created:
    app.name = APP_NAME
    app.provider = provider
    app.meta_launch_url = CODER_ACCESS_URL
    app.save()

for scope in ScopeMapping.objects.filter(scope_name__in=["openid", "email", "profile"]):
    provider.property_mappings.add(scope)

print("CODER_OIDC_CLIENT_ID", provider.client_id)
if os.environ.get("PRINT_CODER_OIDC_CLIENT_SECRET") == "1":
    print("CODER_OIDC_CLIENT_SECRET", provider.client_secret)
else:
    print("CODER_OIDC_CLIENT_SECRET", "[set PRINT_CODER_OIDC_CLIENT_SECRET=1 to print]")
print("CODER_OIDC_ISSUER_URL", f"{AUTHENTIK_PUBLIC_URL}/application/o/{app.slug}/")
print("CODER_ACCESS_URL", CODER_ACCESS_URL)
