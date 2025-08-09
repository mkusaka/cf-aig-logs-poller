import { Env } from './types';

/**
 * Get Google access token using Service Account
 * Uses JWT Bearer Token authentication flow
 */
export async function getGoogleAccessToken(
  env: Env,
  scope: string
): Promise<string> {
  const jwt = await createJWT(env, scope);
  
  const response = await fetch(env.GCP_TOKEN_URI, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Failed to get Google access token: ${response.status} ${errorText}`);
  }

  const result = await response.json<{ access_token: string; expires_in: number }>();
  return result.access_token;
}

/**
 * Create JWT for Service Account
 */
async function createJWT(env: Env, scope: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  
  const header = {
    alg: 'RS256',
    typ: 'JWT',
  };

  const claims = {
    iss: env.GCP_SA_EMAIL,
    scope,
    aud: env.GCP_TOKEN_URI,
    iat: now,
    exp: now + 3600, // Expires in 1 hour
  };

  // Base64URL encode function
  const base64url = (data: string | Uint8Array): string => {
    const base64 = typeof data === 'string' 
      ? btoa(data)
      : btoa(String.fromCharCode(...data));
    return base64
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=/g, '');
  };

  // Encode header and payload
  const encodedHeader = base64url(JSON.stringify(header));
  const encodedClaims = base64url(JSON.stringify(claims));
  const signatureInput = `${encodedHeader}.${encodedClaims}`;

  // Create signature
  const signature = await signRS256(env.GCP_SA_PRIVATE_KEY_PEM, signatureInput);
  const encodedSignature = base64url(signature);

  return `${signatureInput}.${encodedSignature}`;
}

/**
 * Create RS256 signature
 */
async function signRS256(
  privateKeyPem: string,
  data: string
): Promise<Uint8Array> {
  // Extract actual key data from PEM format
  const keyData = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\\n/g, '\n') // Convert escaped newlines to actual newlines
    .replace(/\s/g, ''); // Remove whitespace

  // Base64 decode
  const binaryKey = Uint8Array.from(atob(keyData), c => c.charCodeAt(0));

  // Import as CryptoKey
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  );

  // Create signature
  const signature = await crypto.subtle.sign(
    {
      name: 'RSASSA-PKCS1-v1_5',
    },
    cryptoKey,
    new TextEncoder().encode(data)
  );

  return new Uint8Array(signature);
}

/**
 * Simple implementation to cache access tokens (optional)
 * Uses KV store to cache tokens for a certain period
 */
export async function getCachedAccessToken(
  env: Env,
  scope: string
): Promise<string> {
  const cacheKey = `google_token:${scope}`;
  
  // Try to get from cache
  const cached = await env.STATE_KV.get<{ token: string; expires: number }>(
    cacheKey,
    'json'
  );

  if (cached && cached.expires > Date.now()) {
    return cached.token;
  }

  // Get new token
  const token = await getGoogleAccessToken(env, scope);
  
  // Save to cache (valid for 55 minutes)
  await env.STATE_KV.put(
    cacheKey,
    JSON.stringify({
      token,
      expires: Date.now() + 55 * 60 * 1000,
    }),
    {
      expirationTtl: 55 * 60, // Auto-delete after 55 minutes
    }
  );

  return token;
}