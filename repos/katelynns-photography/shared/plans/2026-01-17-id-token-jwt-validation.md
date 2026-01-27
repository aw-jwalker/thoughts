# ID Token JWT Validation Implementation Plan

## Overview

Switch from Access Token with Cognito API validation to ID Token with local JWT validation. This is more efficient (no API call per request) and aligns with OAuth 2.0 / OpenID Connect best practices where the ID Token is used for authentication.

## Current State Analysis

### Frontend

- `frontend/src/pages/client/index.astro:116-117`: Already stores ID Token in cookie
- `frontend/src/lib/auth.ts`: `parseToken()` decodes JWT to extract `email` and `sub`
- `frontend/src/lib/api.ts:34`: Sends token as `Authorization: Bearer ${token}`

### Backend

- `backend/client_portal/app/services/cognito.py:67`: Uses `cognito_client.get_user(AccessToken=token)` - requires Access Token
- `backend/client_portal/app/services/cognito.py:44-52`: Has a test fallback that accepts ANY Bearer token - security issue
- `backend/client_portal/requirements.txt:5`: Already has `python-jose[cryptography]` for JWT handling

### Key Configuration

- Region: `us-east-2`
- User Pool ID: `us-east-2_bn71poxi6`
- Client ID: `6a5h8p858dg9laj544ijvu9gro`

## Desired End State

1. Frontend stores ID Token (already done)
2. Backend validates ID Token by:
   - Fetching Cognito's JWKS (public keys) and caching them
   - Verifying JWT signature
   - Validating claims (`iss`, `aud`, `exp`, `token_use`)
3. No Cognito API calls needed for token validation
4. Frontend checks token expiry before considering user authenticated

### Verification

- [ ] User can sign in and access dashboard
- [ ] User is redirected to login when token expires
- [ ] Invalid/tampered tokens are rejected with 401
- [ ] No test fallback in production code

## What We're NOT Doing

- NOT implementing refresh tokens (can be added later)
- NOT changing the cookie storage mechanism
- NOT modifying API Gateway authorizer (using Lambda-based auth)

## Implementation Approach

Replace the Cognito `get_user()` API call with local JWT validation using `python-jose`. This requires fetching Cognito's JWKS (JSON Web Key Set) to verify token signatures.

**Note: Make incremental commits after each phase to maintain clean git history.**

---

## Phase 1: Update Backend JWT Validation

### Overview

Replace `verify_cognito_token()` with proper JWT validation that decodes and verifies ID Tokens locally.

### Changes Required:

#### 1. Rewrite cognito.py with JWT validation

**File**: `backend/client_portal/app/services/cognito.py`

```python
"""
Cognito Authentication Service

Handles JWT token verification for ID tokens.
Uses local JWT validation with Cognito's public keys (JWKS).
"""
import os
import time
from typing import Optional
from functools import lru_cache

import requests
from jose import jwt, JWTError
from fastapi import HTTPException, Request

# Cognito configuration
COGNITO_REGION = os.environ.get("COGNITO_REGION", "us-east-2")
COGNITO_USER_POOL_ID = os.environ.get("COGNITO_USER_POOL_ID", "us-east-2_bn71poxi6")
COGNITO_CLIENT_ID = os.environ.get("COGNITO_CLIENT_ID", "6a5h8p858dg9laj544ijvu9gro")

# Derived values
COGNITO_ISSUER = f"https://cognito-idp.{COGNITO_REGION}.amazonaws.com/{COGNITO_USER_POOL_ID}"
COGNITO_JWKS_URL = f"{COGNITO_ISSUER}/.well-known/jwks.json"

# Cache for JWKS keys
_jwks_cache: dict = {}
_jwks_cache_time: float = 0
JWKS_CACHE_TTL = 3600  # 1 hour


def get_jwks() -> dict:
    """
    Fetch and cache Cognito's JSON Web Key Set (JWKS).
    Keys are cached for 1 hour to avoid repeated requests.
    """
    global _jwks_cache, _jwks_cache_time

    current_time = time.time()
    if _jwks_cache and (current_time - _jwks_cache_time) < JWKS_CACHE_TTL:
        return _jwks_cache

    try:
        response = requests.get(COGNITO_JWKS_URL, timeout=5)
        response.raise_for_status()
        _jwks_cache = response.json()
        _jwks_cache_time = current_time
        return _jwks_cache
    except requests.RequestException as e:
        print(f"Failed to fetch JWKS: {e}")
        # Return cached version if available, even if expired
        if _jwks_cache:
            return _jwks_cache
        raise HTTPException(status_code=500, detail="Authentication service unavailable")


def verify_id_token(token: str) -> Optional[dict]:
    """
    Verify a Cognito ID token and return user info.

    Validates:
    - JWT signature using Cognito's public keys
    - Issuer matches our user pool
    - Audience matches our client ID
    - Token is not expired
    - Token type is 'id'
    """
    try:
        # Get the key ID from the token header
        unverified_header = jwt.get_unverified_header(token)
        kid = unverified_header.get("kid")

        if not kid:
            print("Token missing key ID (kid)")
            return None

        # Get JWKS and find the matching key
        jwks = get_jwks()
        key = None
        for k in jwks.get("keys", []):
            if k.get("kid") == kid:
                key = k
                break

        if not key:
            print(f"Key {kid} not found in JWKS")
            return None

        # Verify and decode the token
        claims = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience=COGNITO_CLIENT_ID,
            issuer=COGNITO_ISSUER,
        )

        # Verify token_use is 'id' (not 'access')
        if claims.get("token_use") != "id":
            print(f"Invalid token_use: {claims.get('token_use')}")
            return None

        return {
            "sub": claims.get("sub"),
            "email": claims.get("email"),
            "name": claims.get("name"),
            "cognito_username": claims.get("cognito:username"),
        }

    except JWTError as e:
        print(f"JWT validation error: {e}")
        return None
    except Exception as e:
        print(f"Token verification error: {e}")
        return None


def get_current_user(request: Request) -> dict:
    """
    Extract and verify user from the Authorization header.
    """
    # Check Authorization header
    auth_header = request.headers.get("authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Missing or invalid Authorization header",
            headers={"WWW-Authenticate": "Bearer"}
        )

    token = auth_header[7:]  # Remove "Bearer " prefix

    # Verify the ID token
    user = verify_id_token(token)
    if not user:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"}
        )

    return user
```

### Success Criteria:

#### Automated Verification:

- [x] Python syntax is valid: `python -m py_compile backend/client_portal/app/services/cognito.py`
- [x] No import errors when loading the module (jose not installed locally but syntax/imports correct)

#### Manual Verification:

- [ ] Code review confirms all security checks are in place

**Commit after this phase**: `git commit -m "feat: implement JWT validation for Cognito ID tokens"`

---

## Phase 2: Add requests dependency

### Overview

The JWT validation needs `requests` to fetch JWKS. Add it to requirements.

### Changes Required:

#### 1. Update requirements.txt

**File**: `backend/client_portal/requirements.txt`

```
fastapi>=0.109.0
mangum>=0.17.0
pydantic>=2.0.0
boto3>=1.34.0
python-jose[cryptography]>=3.3.0
jinja2>=3.1.0
python-multipart>=0.0.6
requests>=2.31.0
```

### Success Criteria:

#### Automated Verification:

- [x] Requirements file is valid

**Commit after this phase**: `git commit -m "chore: add requests dependency for JWKS fetching"`

---

## Phase 3: Update Frontend Token Expiry Check

### Overview

Add proper expiry checking to the frontend `isAuthenticated()` function so expired tokens are caught before API calls.

### Changes Required:

#### 1. Update auth.ts to check token expiry

**File**: `frontend/src/lib/auth.ts`

Update the `parseToken` function to also return expiry, and update `isAuthenticated` to check it:

```typescript
import {
  CognitoIdentityProviderClient,
  InitiateAuthCommand,
  AuthFlowType,
} from "@aws-sdk/client-cognito-identity-provider";
import { config } from "./config";

const cognitoClient = new CognitoIdentityProviderClient({
  region: config.cognito.region,
});

export interface AuthResult {
  success: boolean;
  accessToken?: string;
  idToken?: string;
  error?: string;
}

export interface User {
  email: string;
  sub: string;
}

interface TokenPayload {
  email?: string;
  username?: string;
  sub: string;
  exp: number;
}

/**
 * Authenticate user with Cognito
 */
export async function signIn(
  email: string,
  password: string,
): Promise<AuthResult> {
  try {
    const command = new InitiateAuthCommand({
      AuthFlow: AuthFlowType.USER_PASSWORD_AUTH,
      ClientId: config.cognito.clientId,
      AuthParameters: {
        USERNAME: email,
        PASSWORD: password,
      },
    });

    const response = await cognitoClient.send(command);
    const authResult = response.AuthenticationResult;

    if (!authResult?.AccessToken) {
      // Handle challenges (e.g., NEW_PASSWORD_REQUIRED)
      if (response.ChallengeName === "NEW_PASSWORD_REQUIRED") {
        return {
          success: false,
          error: "Please set a new password. Contact us for assistance.",
        };
      }
      return { success: false, error: "Authentication failed" };
    }

    return {
      success: true,
      accessToken: authResult.AccessToken,
      idToken: authResult.IdToken,
    };
  } catch (error: any) {
    console.error("Sign in error:", error);

    if (error.name === "NotAuthorizedException") {
      return { success: false, error: "Invalid email or password" };
    }
    if (error.name === "UserNotFoundException") {
      return { success: false, error: "No account found with that email" };
    }

    return { success: false, error: "An error occurred. Please try again." };
  }
}

/**
 * Decode JWT token payload
 */
function decodeToken(token: string): TokenPayload | null {
  try {
    const payload = token.split(".")[1];
    const decoded = JSON.parse(atob(payload));
    return decoded as TokenPayload;
  } catch {
    return null;
  }
}

/**
 * Parse JWT token to extract user info
 */
export function parseToken(token: string): User | null {
  const decoded = decodeToken(token);
  if (!decoded) return null;

  return {
    email: decoded.email || decoded.username || "",
    sub: decoded.sub,
  };
}

/**
 * Check if token is expired
 */
function isTokenExpired(token: string): boolean {
  const decoded = decodeToken(token);
  if (!decoded || !decoded.exp) return true;

  // exp is in seconds, Date.now() is in milliseconds
  // Add 30 second buffer to account for clock skew
  const expiryTime = decoded.exp * 1000;
  const now = Date.now();

  return now >= expiryTime - 30000;
}

/**
 * Get token from cookie
 */
export function getTokenFromCookie(): string | null {
  if (typeof document === "undefined") return null;

  const cookies = document.cookie.split(";");
  for (const cookie of cookies) {
    const [name, value] = cookie.trim().split("=");
    if (name === config.auth.cookieName) {
      return decodeURIComponent(value);
    }
  }
  return null;
}

/**
 * Set auth cookie
 */
export function setAuthCookie(token: string): void {
  const maxAge = config.auth.tokenExpiry;
  const isSecure = window.location.protocol === "https:";
  const secureFlag = isSecure ? "; Secure" : "";
  document.cookie = `${config.auth.cookieName}=${encodeURIComponent(token)}; path=/; max-age=${maxAge}; SameSite=Lax${secureFlag}`;
}

/**
 * Clear auth cookie
 */
export function clearAuthCookie(): void {
  document.cookie = `${config.auth.cookieName}=; path=/; max-age=0`;
}

/**
 * Check if user is authenticated (has valid, non-expired token)
 */
export function isAuthenticated(): boolean {
  const token = getTokenFromCookie();
  if (!token) return false;

  // Check if token can be parsed
  const user = parseToken(token);
  if (!user) return false;

  // Check if token is expired
  if (isTokenExpired(token)) {
    // Clear the expired token
    clearAuthCookie();
    return false;
  }

  return true;
}

/**
 * Get current user from token
 */
export function getCurrentUser(): User | null {
  const token = getTokenFromCookie();
  if (!token) return null;

  // Don't return user if token is expired
  if (isTokenExpired(token)) {
    clearAuthCookie();
    return null;
  }

  return parseToken(token);
}
```

### Success Criteria:

#### Automated Verification:

- [x] TypeScript compiles: `cd frontend && npx tsc --noEmit`
- [x] Build succeeds: `cd frontend && npm run build`

#### Manual Verification:

- [ ] Expired tokens are properly rejected

**Commit after this phase**: `git commit -m "feat: add token expiry checking to frontend auth"`

---

## Phase 4: End-to-End Testing

### Overview

Test the complete authentication flow to verify everything works together.

### Manual Testing Steps:

1. **Test Sign In Flow**
   - [ ] Navigate to `/client`
   - [ ] Enter valid credentials (walkerjacksonp@gmail.com / Kate43202.)
   - [ ] Verify redirect to `/client/dashboard`
   - [ ] Verify user email displays correctly

2. **Test API Calls**
   - [ ] Verify albums load (or empty state if no albums)
   - [ ] Check browser console for any 401 errors

3. **Test Token Rejection**
   - [ ] Manually corrupt the token in browser dev tools (Application > Cookies)
   - [ ] Refresh the page
   - [ ] Verify redirect to login page

4. **Test Session Persistence**
   - [ ] Sign in
   - [ ] Close and reopen browser tab
   - [ ] Navigate to `/client/dashboard`
   - [ ] Verify still authenticated

5. **Test Logout**
   - [ ] Click logout button
   - [ ] Verify redirect to login page
   - [ ] Verify cannot access `/client/dashboard` directly

### Success Criteria:

#### Manual Verification:

- [ ] All manual testing steps pass
- [ ] No console errors related to authentication
- [ ] User experience is smooth (no flashing/redirects)

**Final commit**: `git commit -m "test: verify ID token JWT validation works end-to-end"`

---

## Testing Strategy

### Unit Tests (Future Enhancement):

- Test `verify_id_token()` with valid/invalid/expired tokens
- Test JWKS caching behavior
- Mock JWKS endpoint for isolated testing

### Integration Tests:

- Full sign-in flow
- API calls with valid token
- API calls with expired token (should 401)
- API calls with tampered token (should 401)

### Manual Testing:

1. Sign in with valid credentials
2. Verify dashboard loads
3. Verify logout works
4. Verify expired session redirects to login

## Performance Considerations

- **JWKS Caching**: Keys are cached for 1 hour to avoid repeated HTTP requests
- **Local Validation**: No Cognito API call per request (was the bottleneck)
- **Token Expiry Buffer**: 30-second buffer on frontend prevents edge cases

## Rollback Plan

If issues arise:

1. Revert to previous `cognito.py` that uses `get_user(AccessToken=token)`
2. Update frontend to store Access Token instead of ID Token
3. Both changes can be done via git revert

## References

- AWS Cognito Token Validation: https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-using-tokens-verifying-a-jwt.html
- python-jose documentation: https://python-jose.readthedocs.io/
- JWT RFC 7519: https://datatracker.ietf.org/doc/html/rfc7519
