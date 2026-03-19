# Authentik OIDC setup for Coder

Configure Authentik as the OIDC provider for Coder so users log in with Authentik (no Coder password).

## Important: First-time setup screen vs login page

Coder’s **“Welcome — create your first admin user”** screen only shows **GitHub** and **Email/Password**. **OIDC (Authentik) does not appear on that screen.** This is how Coder’s first-user wizard works.

**What to do:**

1. On the first-time setup page, create the first admin using **Email and Password** (or GitHub if you use it). Do **not** set `CODER_DISABLE_PASSWORD_AUTH=true` until after this step, or the form may not work.
2. After the first user is created, you are logged in. To use OIDC from then on: log out (or open Coder in a private window) and go to the **login** page. The **OIDC / “Sign in with …”** option appears there for all users (including the admin you just created).
3. Optional: set **`CODER_OIDC_SIGN_IN_TEXT="Sign in with Authentik"`** so the button is clearly labeled. Optional: set **`CODER_DISABLE_PASSWORD_AUTH=true`** after the first user exists if you want OIDC-only for future logins.

So: use **password (or GitHub) once** on the setup screen, then use **OIDC (Authentik)** on the normal login page.

## 1. Create an OIDC provider in Authentik

1. In Authentik Admin: **Applications** → **Providers** → **Create**.
2. Type: **OpenID Connect Provider** (or **OAuth2/OpenID Provider**).
3. **Name:** e.g. `Coder`.
4. **Authorization flow:** Choose a flow that includes consent if required (e.g. default provider authorization).
5. **Client type:** Confidential.
6. **Redirect URIs:** Add exactly:
   ```text
   https://<CODER_ACCESS_URL>/api/v2/users/oidc/callback
   ```
   Example: `https://dev.example.com/api/v2/users/oidc/callback`. No trailing slash; protocol and host must match Coder’s public URL.
7. **Client ID** and **Client Secret:** Generate or set; you’ll give these to Coder.
8. **Advanced / Protocol settings:**
   - **Subject mode:** Set to **Based on the User's Hashed ID** (or another stable sub) so the same user always gets the same `sub` claim. This avoids duplicate Coder users when the subject changes.
9. Save the provider.

## 2. Create an application

1. **Applications** → **Applications** → **Create**.
2. **Name:** e.g. `Coder`.
3. **Provider:** Select the provider you created.
4. **Launch URL:** Optional; e.g. Coder’s URL.
5. Save.

## 3. Configure Coder

Set these environment variables on Coder (e.g. in your Compose or K8s deployment):

| Variable | Value |
|----------|--------|
| **CODER_ACCESS_URL** | Your Coder public URL (e.g. `https://dev.example.com`) |
| **CODER_OIDC_ISSUER_URL** | Authentik OIDC issuer. Often: `https://<authentik-host>/application/o/<application-slug>/` (see below). |
| **CODER_OIDC_CLIENT_ID** | Client ID from the Authentik provider. |
| **CODER_OIDC_CLIENT_SECRET** | Client secret from the Authentik provider. |
| **CODER_OIDC_EMAIL_FIELD** | Claim for email (e.g. `email`). |
| **CODER_OIDC_USERNAME_FIELD** | Claim for username (e.g. `preferred_username`). |
| **CODER_DISABLE_PASSWORD_AUTH** | `true` (optional; leave `false` until after you create the first admin with password — see above). |
| **CODER_OIDC_SIGN_IN_TEXT** | Optional. e.g. `Sign in with Authentik` so the login button is clear. |

**Finding the issuer URL:** In Authentik, open the provider or application and check the **OpenID configuration** or **Issuer** field. It is often:

```text
https://auth.example.com/application/o/<application-slug>/
```

Coder will append `.well-known/openid-configuration` to this URL for discovery.

## 4. Resolving common issues

- **Redirect URI mismatch:** The redirect URI in Authentik must match exactly what Coder sends (including `https` and no trailing slash). Use the exact value from Coder’s OIDC docs: `https://<CODER_ACCESS_URL>/api/v2/users/oidc/callback`.
- **Subject (sub) changes:** If the same human gets different Coder users over time, fix the subject mode in Authentik so `sub` is stable (e.g. hashed user id).
- **Coder v2 and Authentik:** Some setups need **Authorization** in the provider set to `default-provider-authorization-explicit-consent`. If login fails, check Authentik logs and Coder logs for OIDC errors.

See also: [Authentik issue #5378](https://github.com/goauthentik/authentik/issues/5378) (Coder + Authentik OIDC) and [Coder OIDC Setup](https://coder.com/docs/admin/users/oidc-auth).
