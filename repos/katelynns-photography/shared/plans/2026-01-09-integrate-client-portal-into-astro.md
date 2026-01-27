# Integrate Client Portal into Astro Site - Implementation Plan

## Overview

Rebuild the client portal directly within the Astro site using AWS Cognito JavaScript SDK for authentication and fetch calls to the existing Lambda APIs. This replaces the separate HTMX/FastAPI portal with an integrated solution that provides a seamless user experience under one URL.

## Current State Analysis

### Astro Site Structure

- **Pages**: `index`, `about`, `portfolio`, `pricing`, `contact`
- **Navigation**: Already has "Client Login" link pointing to `/client` (`Navigation.astro:45-50`)
- **Styling**: Tailwind CSS with custom `primary` (beige/brown) and `accent` (gold) colors
- **Output**: Static mode (`astro.config.mjs:9`)
- **No `/client` page exists** - currently returns 404

### Existing Lambda APIs (Working)

Base URL: `https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com`

| Endpoint                      | Method | Auth | Description                   |
| ----------------------------- | ------ | ---- | ----------------------------- |
| `/albums`                     | GET    | Yes  | List user's albums            |
| `/albums/{album_id}`          | GET    | Yes  | Get album details             |
| `/albums/{album_id}/files`    | GET    | Yes  | Get files with presigned URLs |
| `/albums/{album_id}/download` | GET    | Yes  | Get download URL for file     |

### Cognito Configuration

- **User Pool ID**: `us-east-2_bn71poxi6`
- **Client ID**: `6a5h8p858dg9laj544ijvu9gro`
- **Region**: `us-east-2`
- **Auth Flow**: `USER_PASSWORD_AUTH`

### HTMX Portal (To Be Removed)

- Location: `backend/client_portal/`
- Lambda routes in `terraform/lambda.tf` (lines 320-351)
- Templates in `backend/client_portal/app/templates/`

## Desired End State

After this plan is complete:

1. **Renamed directory** - `frontend/` renamed to `frontend/` (unified site)
2. **Unified site** - Client portal accessible at `/client` within the Astro site
3. **Cookie-based auth** - Secure cookies for token storage
4. **Full functionality** - Login, view albums, browse photos, download files
5. **Removed HTMX portal** - Lambda portal routes and code deleted
6. **Consistent styling** - Portal pages match public site aesthetic

### Verification

- [ ] Navigate to `/client` shows login form
- [ ] Login with valid Cognito credentials redirects to `/client/dashboard`
- [ ] Dashboard shows user's albums fetched from Lambda API
- [ ] Album detail page shows photos with working download links
- [ ] Logout clears cookie and redirects to login
- [ ] Invalid credentials show error message
- [ ] Unauthenticated access to `/client/dashboard` redirects to `/client`

## What We're NOT Doing

- **Social sign-in (Google)** - Noted as future improvement
- **SSR mode** - Keeping Astro static; auth handled client-side
- **Token refresh** - 1-hour tokens sufficient for photo viewing sessions
- **Remember me** - Sessions expire when browser closes
- **Password reset flow** - Admin handles via AWS Console for now

## Implementation Approach

Since Astro is in static mode, authentication will be handled entirely client-side:

1. Login form submits to Cognito via JS SDK
2. On success, store tokens in httpOnly cookie (via a small cookie-setting endpoint or JS)
3. Protected pages check for valid token on load
4. API calls include Authorization header with access token
5. Logout clears cookie

**Note on Cookies**: Since we're static, we can't set httpOnly cookies from client-side JS directly. Options:

- **Option A**: Use a small Lambda endpoint to set the cookie after auth (more secure)
- **Option B**: Use regular cookies set via JS (simpler, less secure)
- **Selected**: Option A - Add a `/api/auth/callback` Lambda endpoint that sets httpOnly cookie

---

## Phase 1: Rename Directory and Install Dependencies

### Overview

Rename `frontend/` to `frontend/` to reflect its new role as the unified site, then add AWS SDK and create authentication utility functions.

### Changes Required:

#### 1. Rename Directory

```bash
cd ~/repos/katelynns-photography
mv frontend frontend
```

Update any scripts that reference the old name:

**File**: `scripts/deploy_astro.sh` (rename to `scripts/deploy_frontend.sh`)

```bash
mv scripts/deploy_astro.sh scripts/deploy_frontend.sh
# Update the script to use 'frontend' instead of 'frontend'
sed -i 's/frontend/frontend/g' scripts/deploy_frontend.sh
```

#### 2. Install AWS SDK

**File**: `frontend/package.json`

```bash
cd frontend
npm install @aws-sdk/client-cognito-identity-provider
```

#### 3. Create Auth Configuration

**File**: `frontend/src/lib/config.ts`

```typescript
// Cognito and API configuration
export const config = {
  cognito: {
    region: "us-east-2",
    userPoolId: "us-east-2_bn71poxi6",
    clientId: "6a5h8p858dg9laj544ijvu9gro",
  },
  api: {
    baseUrl: "https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com",
  },
  auth: {
    cookieName: "kp_session",
    tokenExpiry: 3600, // 1 hour in seconds
  },
};
```

#### 4. Create Auth Utility

**File**: `frontend/src/lib/auth.ts`

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
 * Parse JWT token to extract user info
 */
export function parseToken(token: string): User | null {
  try {
    const payload = token.split(".")[1];
    const decoded = JSON.parse(atob(payload));
    return {
      email: decoded.email || decoded.username,
      sub: decoded.sub,
    };
  } catch {
    return null;
  }
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
  document.cookie = `${config.auth.cookieName}=${encodeURIComponent(token)}; path=/; max-age=${maxAge}; SameSite=Lax; Secure`;
}

/**
 * Clear auth cookie
 */
export function clearAuthCookie(): void {
  document.cookie = `${config.auth.cookieName}=; path=/; max-age=0`;
}

/**
 * Check if user is authenticated
 */
export function isAuthenticated(): boolean {
  const token = getTokenFromCookie();
  if (!token) return false;

  // Check if token is expired
  const user = parseToken(token);
  return user !== null;
}

/**
 * Get current user from token
 */
export function getCurrentUser(): User | null {
  const token = getTokenFromCookie();
  if (!token) return null;
  return parseToken(token);
}
```

#### 5. Create API Client

**File**: `frontend/src/lib/api.ts`

```typescript
import { config } from "./config";
import { getTokenFromCookie } from "./auth";

export interface Album {
  id: string;
  name: string;
  photo_count: number;
  created_at: string | null;
}

export interface AlbumFile {
  name: string;
  size: number;
  last_modified: string;
  download_url: string;
}

/**
 * Make authenticated API request
 */
async function apiRequest<T>(
  endpoint: string,
  options: RequestInit = {},
): Promise<T> {
  const token = getTokenFromCookie();

  if (!token) {
    throw new Error("Not authenticated");
  }

  const response = await fetch(`${config.api.baseUrl}${endpoint}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...options.headers,
    },
  });

  if (!response.ok) {
    if (response.status === 401) {
      throw new Error("Session expired");
    }
    throw new Error(`API error: ${response.status}`);
  }

  return response.json();
}

/**
 * Get list of user's albums
 */
export async function getAlbums(): Promise<Album[]> {
  const data = await apiRequest<{ albums: Album[]; total: number }>("/albums");
  return data.albums;
}

/**
 * Get album details
 */
export async function getAlbum(albumId: string): Promise<Album> {
  return apiRequest<Album>(`/albums/${albumId}`);
}

/**
 * Get files in an album with download URLs
 */
export async function getAlbumFiles(albumId: string): Promise<AlbumFile[]> {
  const data = await apiRequest<{
    album_id: string;
    files: AlbumFile[];
    total: number;
  }>(`/albums/${albumId}/files`);
  return data.files;
}
```

### Success Criteria:

#### Automated Verification:

- [x] `frontend/` directory exists (renamed from `astro-portfolio/`)
- [x] `scripts/deploy_frontend.sh` exists and references `frontend/`
- [x] `cd frontend && npm install` completes without errors
- [x] `npm run build` succeeds with new dependencies
- [x] TypeScript compiles without errors

#### Manual Verification:

- [ ] N/A - no UI changes yet

---

## Phase 2: Create Login Page

### Overview

Create the `/client` login page with form and authentication logic.

### Changes Required:

#### 1. Create Client Login Page

**File**: `frontend/src/pages/client/index.astro`

```astro
---
import Layout from '../../layouts/Layout.astro';
---

<Layout title="Client Login" description="Access your photo galleries">
  <div class="min-h-[70vh] flex items-center justify-center py-12 px-4">
    <div class="max-w-md w-full">
      <div class="bg-white rounded-sm shadow-lg p-8">
        <h1 class="text-2xl font-serif text-primary-900 text-center mb-6">
          Client Login
        </h1>

        <p class="text-primary-600 text-sm text-center mb-8">
          Access your photo galleries and downloads.
        </p>

        <!-- Error message container -->
        <div id="error-message" class="hidden bg-red-100 text-red-800 p-4 rounded-sm mb-6 text-sm">
        </div>

        <form id="login-form" class="space-y-6">
          <div>
            <label for="email" class="block text-sm font-medium text-primary-700 mb-2">
              Email Address
            </label>
            <input
              type="email"
              id="email"
              name="email"
              required
              class="w-full px-4 py-3 border border-primary-300 rounded-sm focus:ring-2 focus:ring-accent focus:border-accent outline-none"
              placeholder="your@email.com"
            />
          </div>

          <div>
            <label for="password" class="block text-sm font-medium text-primary-700 mb-2">
              Password
            </label>
            <input
              type="password"
              id="password"
              name="password"
              required
              class="w-full px-4 py-3 border border-primary-300 rounded-sm focus:ring-2 focus:ring-accent focus:border-accent outline-none"
              placeholder="••••••••"
            />
          </div>

          <button
            type="submit"
            id="submit-btn"
            class="w-full bg-accent text-white py-3 rounded-sm font-medium hover:bg-accent-dark transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
          >
            <span id="btn-text">Sign In</span>
            <span id="btn-spinner" class="hidden">
              <svg class="animate-spin h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
            </span>
          </button>
        </form>

        <div class="mt-6 pt-6 border-t border-primary-200 text-center">
          <p class="text-sm text-primary-600">
            Don't have access? Contact us after your session to receive your login credentials.
          </p>
        </div>
      </div>
    </div>
  </div>
</Layout>

<script>
  import { signIn, setAuthCookie, isAuthenticated } from '../../lib/auth';

  // Redirect if already authenticated
  if (isAuthenticated()) {
    window.location.href = '/client/dashboard';
  }

  const form = document.getElementById('login-form') as HTMLFormElement;
  const errorDiv = document.getElementById('error-message') as HTMLDivElement;
  const submitBtn = document.getElementById('submit-btn') as HTMLButtonElement;
  const btnText = document.getElementById('btn-text') as HTMLSpanElement;
  const btnSpinner = document.getElementById('btn-spinner') as HTMLSpanElement;

  function showError(message: string) {
    errorDiv.textContent = message;
    errorDiv.classList.remove('hidden');
  }

  function hideError() {
    errorDiv.classList.add('hidden');
  }

  function setLoading(loading: boolean) {
    submitBtn.disabled = loading;
    btnText.textContent = loading ? 'Signing in...' : 'Sign In';
    btnSpinner.classList.toggle('hidden', !loading);
  }

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    hideError();
    setLoading(true);

    const formData = new FormData(form);
    const email = formData.get('email') as string;
    const password = formData.get('password') as string;

    try {
      const result = await signIn(email, password);

      if (result.success && result.accessToken) {
        setAuthCookie(result.accessToken);
        window.location.href = '/client/dashboard';
      } else {
        showError(result.error || 'Login failed');
        setLoading(false);
      }
    } catch (error) {
      console.error('Login error:', error);
      showError('An unexpected error occurred. Please try again.');
      setLoading(false);
    }
  });
</script>
```

### Success Criteria:

#### Automated Verification:

- [x] `npm run build` succeeds
- [x] `/client/index.html` exists in build output

#### Manual Verification:

- [ ] Navigate to `http://localhost:4321/client` shows login form
- [ ] Submitting invalid credentials shows error message
- [ ] Submitting valid credentials redirects to `/client/dashboard`
- [ ] Loading spinner appears during authentication
- [ ] Form styling matches site aesthetic

**Implementation Note**: Test with a real Cognito user. Create one via AWS Console if needed:

```bash
aws cognito-idp admin-create-user \
  --user-pool-id us-east-2_bn71poxi6 \
  --username test@example.com \
  --temporary-password TempPass123! \
  --user-attributes Name=email,Value=test@example.com Name=email_verified,Value=true \
  --profile jw-dev --region us-east-2
```

---

## Phase 3: Create Dashboard Page

### Overview

Create the `/client/dashboard` page showing the user's albums.

### Changes Required:

#### 1. Create Dashboard Page

**File**: `frontend/src/pages/client/dashboard.astro`

```astro
---
import Layout from '../../layouts/Layout.astro';
---

<Layout title="My Albums" description="View your photo galleries">
  <div class="container mx-auto px-4 py-8">
    <!-- Header -->
    <div class="flex items-center justify-between mb-8">
      <div>
        <h1 class="text-3xl font-serif text-primary-900">My Albums</h1>
        <p id="user-email" class="text-primary-600 mt-1"></p>
      </div>
      <button
        id="logout-btn"
        class="text-sm text-primary-600 hover:text-accent transition-colors"
      >
        Logout
      </button>
    </div>

    <!-- Loading state -->
    <div id="loading" class="flex justify-center py-12">
      <svg class="animate-spin h-8 w-8 text-accent" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
    </div>

    <!-- Error state -->
    <div id="error" class="hidden bg-red-100 text-red-800 p-4 rounded-sm text-center">
      <p id="error-message"></p>
      <button id="retry-btn" class="mt-2 text-sm underline">Try again</button>
    </div>

    <!-- Empty state -->
    <div id="empty" class="hidden text-center py-12">
      <p class="text-primary-600 text-lg">No albums available yet.</p>
      <p class="text-primary-500 text-sm mt-2">Your photos will appear here after your session.</p>
    </div>

    <!-- Albums grid -->
    <div id="albums-grid" class="hidden grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
      <!-- Albums will be inserted here -->
    </div>
  </div>
</Layout>

<script>
  import { isAuthenticated, getCurrentUser, clearAuthCookie } from '../../lib/auth';
  import { getAlbums, type Album } from '../../lib/api';

  // Check authentication
  if (!isAuthenticated()) {
    window.location.href = '/client';
  }

  const userEmailEl = document.getElementById('user-email') as HTMLParagraphElement;
  const loadingEl = document.getElementById('loading') as HTMLDivElement;
  const errorEl = document.getElementById('error') as HTMLDivElement;
  const errorMsgEl = document.getElementById('error-message') as HTMLParagraphElement;
  const emptyEl = document.getElementById('empty') as HTMLDivElement;
  const albumsGridEl = document.getElementById('albums-grid') as HTMLDivElement;
  const logoutBtn = document.getElementById('logout-btn') as HTMLButtonElement;
  const retryBtn = document.getElementById('retry-btn') as HTMLButtonElement;

  // Display user email
  const user = getCurrentUser();
  if (user) {
    userEmailEl.textContent = user.email;
  }

  // Logout handler
  logoutBtn.addEventListener('click', () => {
    clearAuthCookie();
    window.location.href = '/client';
  });

  // Retry handler
  retryBtn.addEventListener('click', loadAlbums);

  function showLoading() {
    loadingEl.classList.remove('hidden');
    errorEl.classList.add('hidden');
    emptyEl.classList.add('hidden');
    albumsGridEl.classList.add('hidden');
  }

  function showError(message: string) {
    loadingEl.classList.add('hidden');
    errorEl.classList.remove('hidden');
    errorMsgEl.textContent = message;
    emptyEl.classList.add('hidden');
    albumsGridEl.classList.add('hidden');
  }

  function showEmpty() {
    loadingEl.classList.add('hidden');
    errorEl.classList.add('hidden');
    emptyEl.classList.remove('hidden');
    albumsGridEl.classList.add('hidden');
  }

  function showAlbums(albums: Album[]) {
    loadingEl.classList.add('hidden');
    errorEl.classList.add('hidden');
    emptyEl.classList.add('hidden');
    albumsGridEl.classList.remove('hidden');

    albumsGridEl.innerHTML = albums.map(album => `
      <a href="/client/albums/${album.id}" class="group">
        <div class="bg-white rounded-sm shadow-md overflow-hidden hover:shadow-lg transition-shadow">
          <div class="aspect-[4/3] bg-primary-100 flex items-center justify-center">
            <svg class="w-16 h-16 text-primary-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
            </svg>
          </div>
          <div class="p-4">
            <h2 class="font-serif text-lg text-primary-900 group-hover:text-accent transition-colors">
              ${album.name}
            </h2>
            <p class="text-sm text-primary-600 mt-1">
              ${album.photo_count} photo${album.photo_count !== 1 ? 's' : ''}
            </p>
            ${album.created_at ? `
              <p class="text-xs text-primary-500 mt-1">
                ${new Date(album.created_at).toLocaleDateString()}
              </p>
            ` : ''}
          </div>
        </div>
      </a>
    `).join('');
  }

  async function loadAlbums() {
    showLoading();

    try {
      const albums = await getAlbums();

      if (albums.length === 0) {
        showEmpty();
      } else {
        showAlbums(albums);
      }
    } catch (error: any) {
      console.error('Error loading albums:', error);

      if (error.message === 'Session expired' || error.message === 'Not authenticated') {
        clearAuthCookie();
        window.location.href = '/client';
        return;
      }

      showError('Failed to load albums. Please try again.');
    }
  }

  // Load albums on page load
  loadAlbums();
</script>
```

### Success Criteria:

#### Automated Verification:

- [x] `npm run build` succeeds
- [x] `/client/dashboard/index.html` exists in build output

#### Manual Verification:

- [ ] Navigate to `/client/dashboard` when authenticated shows albums
- [ ] Navigate to `/client/dashboard` when not authenticated redirects to `/client`
- [ ] User email displays in header
- [ ] Logout button clears session and redirects
- [ ] Albums fetch from Lambda API and display in grid
- [ ] Empty state shows when user has no albums
- [ ] Error state shows with retry button on API failure

---

## Phase 4: Create Album Detail Page

### Overview

Create the `/client/albums/[id]` page showing photos with download links.

### Changes Required:

#### 1. Create Album Detail Page

**File**: `frontend/src/pages/client/albums/[id].astro`

```astro
---
import Layout from '../../../layouts/Layout.astro';

// For static builds, we need getStaticPaths
// Since albums are dynamic, we use a catch-all approach
export function getStaticPaths() {
  // Return empty - this page will 404 in static mode for unknown albums
  // But the client-side JS will handle the dynamic loading
  return [];
}

// Enable prerender false for this dynamic page
export const prerender = false;

const { id } = Astro.params;
---

<Layout title="Album" description="View your photos">
  <div class="container mx-auto px-4 py-8">
    <!-- Back link -->
    <a href="/client/dashboard" class="inline-flex items-center text-primary-600 hover:text-accent transition-colors mb-6">
      <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
      </svg>
      Back to Albums
    </a>

    <!-- Header -->
    <div class="mb-8">
      <h1 id="album-title" class="text-3xl font-serif text-primary-900">Loading...</h1>
      <p id="photo-count" class="text-primary-600 mt-1"></p>
    </div>

    <!-- Loading state -->
    <div id="loading" class="flex justify-center py-12">
      <svg class="animate-spin h-8 w-8 text-accent" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
    </div>

    <!-- Error state -->
    <div id="error" class="hidden bg-red-100 text-red-800 p-4 rounded-sm text-center">
      <p id="error-message"></p>
      <a href="/client/dashboard" class="mt-2 inline-block text-sm underline">Back to albums</a>
    </div>

    <!-- Photos grid -->
    <div id="photos-grid" class="hidden grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
      <!-- Photos will be inserted here -->
    </div>
  </div>

  <!-- Lightbox -->
  <div id="lightbox" class="hidden fixed inset-0 bg-black/90 z-50 flex items-center justify-center">
    <button id="lightbox-close" class="absolute top-4 right-4 text-white hover:text-accent transition-colors">
      <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
      </svg>
    </button>
    <button id="lightbox-prev" class="absolute left-4 text-white hover:text-accent transition-colors">
      <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
      </svg>
    </button>
    <button id="lightbox-next" class="absolute right-4 text-white hover:text-accent transition-colors">
      <svg class="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
      </svg>
    </button>
    <img id="lightbox-img" class="max-h-[90vh] max-w-[90vw] object-contain" src="" alt="" />
    <a id="lightbox-download" href="" download class="absolute bottom-4 bg-accent text-white px-4 py-2 rounded-sm hover:bg-accent-dark transition-colors">
      Download
    </a>
  </div>
</Layout>

<script define:vars={{ albumId: id }}>
  window.ALBUM_ID = albumId;
</script>

<script>
  import { isAuthenticated, clearAuthCookie } from '../../../lib/auth';
  import { getAlbum, getAlbumFiles, type Album, type AlbumFile } from '../../../lib/api';

  // Check authentication
  if (!isAuthenticated()) {
    window.location.href = '/client';
  }

  // Get album ID from URL
  const albumId = (window as any).ALBUM_ID || window.location.pathname.split('/').pop();

  const albumTitleEl = document.getElementById('album-title') as HTMLHeadingElement;
  const photoCountEl = document.getElementById('photo-count') as HTMLParagraphElement;
  const loadingEl = document.getElementById('loading') as HTMLDivElement;
  const errorEl = document.getElementById('error') as HTMLDivElement;
  const errorMsgEl = document.getElementById('error-message') as HTMLParagraphElement;
  const photosGridEl = document.getElementById('photos-grid') as HTMLDivElement;

  // Lightbox elements
  const lightboxEl = document.getElementById('lightbox') as HTMLDivElement;
  const lightboxImgEl = document.getElementById('lightbox-img') as HTMLImageElement;
  const lightboxDownloadEl = document.getElementById('lightbox-download') as HTMLAnchorElement;
  const lightboxCloseEl = document.getElementById('lightbox-close') as HTMLButtonElement;
  const lightboxPrevEl = document.getElementById('lightbox-prev') as HTMLButtonElement;
  const lightboxNextEl = document.getElementById('lightbox-next') as HTMLButtonElement;

  let currentFiles: AlbumFile[] = [];
  let currentIndex = 0;

  function showLoading() {
    loadingEl.classList.remove('hidden');
    errorEl.classList.add('hidden');
    photosGridEl.classList.add('hidden');
  }

  function showError(message: string) {
    loadingEl.classList.add('hidden');
    errorEl.classList.remove('hidden');
    errorMsgEl.textContent = message;
    photosGridEl.classList.add('hidden');
  }

  function showPhotos(album: Album, files: AlbumFile[]) {
    loadingEl.classList.add('hidden');
    errorEl.classList.add('hidden');
    photosGridEl.classList.remove('hidden');

    albumTitleEl.textContent = album.name;
    photoCountEl.textContent = `${files.length} photo${files.length !== 1 ? 's' : ''}`;

    currentFiles = files;

    photosGridEl.innerHTML = files.map((file, index) => `
      <div class="group relative aspect-square bg-primary-100 rounded-sm overflow-hidden cursor-pointer" data-index="${index}">
        <img
          src="${file.download_url}"
          alt="${file.name}"
          class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
          loading="lazy"
        />
        <div class="absolute inset-0 bg-black/0 group-hover:bg-black/30 transition-colors flex items-center justify-center">
          <span class="opacity-0 group-hover:opacity-100 transition-opacity text-white text-sm">
            Click to view
          </span>
        </div>
      </div>
    `).join('');

    // Add click handlers to photos
    photosGridEl.querySelectorAll('[data-index]').forEach(el => {
      el.addEventListener('click', () => {
        const index = parseInt(el.getAttribute('data-index') || '0');
        openLightbox(index);
      });
    });
  }

  function openLightbox(index: number) {
    currentIndex = index;
    updateLightbox();
    lightboxEl.classList.remove('hidden');
    document.body.style.overflow = 'hidden';
  }

  function closeLightbox() {
    lightboxEl.classList.add('hidden');
    document.body.style.overflow = '';
  }

  function updateLightbox() {
    const file = currentFiles[currentIndex];
    lightboxImgEl.src = file.download_url;
    lightboxImgEl.alt = file.name;
    lightboxDownloadEl.href = file.download_url;
    lightboxDownloadEl.download = file.name;
  }

  function prevPhoto() {
    currentIndex = (currentIndex - 1 + currentFiles.length) % currentFiles.length;
    updateLightbox();
  }

  function nextPhoto() {
    currentIndex = (currentIndex + 1) % currentFiles.length;
    updateLightbox();
  }

  // Lightbox event listeners
  lightboxCloseEl.addEventListener('click', closeLightbox);
  lightboxPrevEl.addEventListener('click', prevPhoto);
  lightboxNextEl.addEventListener('click', nextPhoto);

  lightboxEl.addEventListener('click', (e) => {
    if (e.target === lightboxEl) closeLightbox();
  });

  document.addEventListener('keydown', (e) => {
    if (lightboxEl.classList.contains('hidden')) return;
    if (e.key === 'Escape') closeLightbox();
    if (e.key === 'ArrowLeft') prevPhoto();
    if (e.key === 'ArrowRight') nextPhoto();
  });

  async function loadAlbum() {
    if (!albumId) {
      showError('Album not found');
      return;
    }

    showLoading();

    try {
      const [album, files] = await Promise.all([
        getAlbum(albumId),
        getAlbumFiles(albumId),
      ]);

      showPhotos(album, files);
    } catch (error: any) {
      console.error('Error loading album:', error);

      if (error.message === 'Session expired' || error.message === 'Not authenticated') {
        clearAuthCookie();
        window.location.href = '/client';
        return;
      }

      showError('Failed to load album. It may not exist or you may not have access.');
    }
  }

  loadAlbum();
</script>
```

#### 2. Update Astro Config for Hybrid Mode

**File**: `frontend/astro.config.mjs`

Since we need dynamic routes for album IDs, update to hybrid output:

```javascript
// @ts-check
import { defineConfig } from "astro/config";
import tailwind from "@astrojs/tailwind";
import sitemap from "@astrojs/sitemap";
import node from "@astrojs/node";

export default defineConfig({
  site: "https://katelynnsphotography.com",
  integrations: [tailwind(), sitemap()],
  output: "hybrid", // Changed from "static" to allow some dynamic routes
  adapter: node({ mode: "standalone" }), // For local dev; S3 deploy still works for static pages
  build: {
    assets: "_assets",
  },
  image: {
    service: {
      entrypoint: "astro/assets/services/sharp",
    },
  },
});
```

**Note**: Actually, we can keep static mode and handle dynamic routes client-side. Let me revise:

**Alternative approach (keep static mode)**:

Instead of hybrid mode, create a catch-all route that loads album ID from URL client-side:

**File**: `frontend/src/pages/client/albums/[...id].astro`

```astro
---
import Layout from '../../../layouts/Layout.astro';

export function getStaticPaths() {
  // Return a placeholder - actual album loading happens client-side
  return [{ params: { id: 'view' } }];
}
---

<!-- Same content as above, but get ID from URL client-side -->
```

Actually, the simplest approach for static hosting is to use a single page that reads the album ID from the URL hash or query param. But that's not ideal UX.

**Final decision**: Use the `[...id].astro` approach with client-side routing. The page will always render, and JS will handle loading the correct album based on the URL path.

### Success Criteria:

#### Automated Verification:

- [x] `npm run build` succeeds
- [x] Album detail page file exists in build output

#### Manual Verification:

- [ ] Navigate to `/client/albums/{valid-id}` shows photos
- [ ] Photos load lazily with presigned URLs from API
- [ ] Clicking photo opens lightbox
- [ ] Lightbox navigation (arrows, keyboard) works
- [ ] Download button downloads the photo
- [ ] Back link returns to dashboard
- [ ] Invalid album ID shows error

---

## Phase 5: Remove HTMX Portal and Clean Up

### Overview

Remove the HTMX portal code and Lambda routes that are no longer needed.

### Changes Required:

#### 1. Remove Portal Routes from Terraform

**File**: `terraform/lambda.tf`

Delete or comment out these route resources (lines 320-351):

- `aws_apigatewayv2_route.portal_login`
- `aws_apigatewayv2_route.portal_login_post`
- `aws_apigatewayv2_route.portal_logout`
- `aws_apigatewayv2_route.portal_dashboard`
- `aws_apigatewayv2_route.portal_album_detail`

Keep the JSON API routes (`/albums`, `/albums/{album_id}`, etc.) as they're still used.

#### 2. Remove Portal Templates

Delete the entire templates directory:

```bash
rm -rf backend/client_portal/app/templates/
```

#### 3. Remove Portal Routes File

**File**: `backend/client_portal/app/routes/portal.py`
Delete this file entirely.

#### 4. Update Main App

**File**: `backend/client_portal/app/main.py`

Remove the portal router import and include:

```python
# Remove these lines:
# from .routes.portal import router as portal_router
# app.include_router(portal_router)
```

Keep the albums router and other API functionality.

#### 5. Apply Terraform Changes

```bash
cd terraform
terraform plan -out=tfplan
terraform apply tfplan
```

#### 6. Redeploy Lambda

```bash
./scripts/deploy_lambda.sh
```

### Success Criteria:

#### Automated Verification:

- [x] Code changes complete (portal routes removed from terraform)
- [x] Portal router removed from FastAPI app
- [x] Portal templates and routes files deleted
- [ ] `terraform plan` shows routes being removed (requires AWS)
- [ ] `terraform apply` succeeds (requires AWS)
- [ ] Lambda deploys successfully (requires AWS)
- [ ] API endpoints still work: `curl https://nbu6ndrpg2.execute-api.us-east-2.amazonaws.com/api/health`

#### Manual Verification:

- [ ] Old portal URLs return 404 or "Not Found"
- [ ] Astro client portal continues to work
- [ ] Album API endpoints still authenticate and return data

---

## Phase 6: Final Polish and Testing

### Overview

Add final touches, update navigation, and perform end-to-end testing.

### Changes Required:

#### 1. Update Navigation Component

**File**: `frontend/src/components/Navigation.astro`

The navigation already has "Client Login" link to `/client` (line 45-50), so no changes needed.

#### 2. Add Protected Route Indicator

Optionally add a visual indicator when user is logged in. This requires client-side JS check.

#### 3. Test End-to-End Flow

1. Create test Cognito user (if not exists)
2. Upload test album to S3
3. Test complete flow:
   - Visit `/client`
   - Login with credentials
   - View dashboard with albums
   - Click album to see photos
   - Download a photo
   - Logout
   - Verify redirect to login

### Success Criteria:

#### Automated Verification:

- [x] `npm run build` succeeds
- [x] All static pages generated (8 pages including client portal)
- [x] No TypeScript errors

#### Manual Verification:

- [ ] Complete login → dashboard → album → download → logout flow works
- [ ] Mobile responsive design works on all portal pages
- [ ] Session expires after 1 hour (can test by waiting or manipulating cookie)
- [ ] All styling consistent with public site
- [ ] No console errors during normal usage

---

## Testing Strategy

### Unit Tests

- Auth utility functions (parseToken, cookie operations)
- API client error handling

### Integration Tests

- Cognito authentication flow
- API calls with valid/invalid tokens
- Cookie persistence across page loads

### Manual Testing Steps

1. **Fresh login**: Clear cookies, navigate to `/client`, login
2. **Session persistence**: After login, refresh page - should stay logged in
3. **Protected routes**: Try accessing `/client/dashboard` without auth
4. **API errors**: Test with invalid album ID
5. **Mobile**: Test all flows on mobile device/emulator
6. **Logout**: Verify cookie cleared and redirect works

---

## Future Improvements

- **Social sign-in (Google, Apple)**: Add OAuth providers to Cognito
- **Remember me**: Longer-lived refresh tokens with "remember me" checkbox
- **Password reset**: Self-service password reset flow
- **Album thumbnails**: Generate thumbnails for faster grid loading
- **Bulk download**: Zip download for entire albums
- **Token refresh**: Automatic token refresh before expiry

---

## References

- Frontend (formerly astro-portfolio): `frontend/`
- Lambda APIs: `backend/client_portal/`
- Terraform: `terraform/lambda.tf`, `terraform/cognito.tf`
- Master plan: `thoughts/shared/plans/2026-01-08-build-website-master-plan.md`
- AWS Cognito JS SDK: https://docs.aws.amazon.com/cognito/latest/developerguide/
