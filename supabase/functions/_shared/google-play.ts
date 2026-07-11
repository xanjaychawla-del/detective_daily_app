// Shared Google Play Developer API helper used by verify-subscription-
// purchase and play-rtdn-webhook. Unlike google-tts.ts's plain API key,
// the Play Developer API requires a signed service-account OAuth bearer
// token -- there is no simpler auth option for server-to-server purchase
// verification.
//
// Secret: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON (the full downloaded service
// account key JSON, as created under Play Console > Setup > API access).

interface ServiceAccountKey {
  client_email: string;
  private_key: string;
}

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const ANDROID_PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher";

function base64UrlEncode(bytes: ArrayBuffer | Uint8Array): string {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (const byte of arr) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(cleaned);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function signJwt(serviceAccount: ServiceAccountKey): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const nowSeconds = Math.floor(Date.now() / 1000);
  const claimSet = {
    iss: serviceAccount.client_email,
    scope: ANDROID_PUBLISHER_SCOPE,
    aud: TOKEN_URL,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  };

  const encodedHeader = base64UrlEncode(new TextEncoder().encode(JSON.stringify(header)));
  const encodedClaimSet = base64UrlEncode(new TextEncoder().encode(JSON.stringify(claimSet)));
  const signingInput = `${encodedHeader}.${encodedClaimSet}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${base64UrlEncode(signature)}`;
}

/** Exchanges the service account's signed JWT for a short-lived (1hr)
 * androidpublisher-scoped access token. Callers should mint one per
 * invocation rather than caching across edge function cold starts -- these
 * calls are infrequent enough (one purchase, one webhook delivery) that
 * the extra round trip isn't worth the complexity of a shared cache. */
export async function mintAccessToken(serviceAccountJson: string): Promise<string> {
  const serviceAccount = JSON.parse(serviceAccountJson) as ServiceAccountKey;
  const assertion = await signJwt(serviceAccount);

  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`google_token_exchange_failed:${response.status}:${text}`);
  }
  const data = JSON.parse(text) as { access_token?: string };
  if (!data.access_token) throw new Error("google_token_exchange_missing_access_token");
  return data.access_token;
}

/** Our internal, app-facing subscription status -- kept intentionally
 * small and matching the `subscriptions.status` check constraint in
 * migration 014. */
export type InternalSubscriptionStatus =
  | "active"
  | "canceled"
  | "in_grace_period"
  | "on_hold"
  | "paused"
  | "expired"
  | "revoked";

function mapSubscriptionState(state: string | undefined): InternalSubscriptionStatus {
  switch (state) {
    case "SUBSCRIPTION_STATE_ACTIVE":
      return "active";
    case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD":
      return "in_grace_period";
    case "SUBSCRIPTION_STATE_ON_HOLD":
      return "on_hold";
    case "SUBSCRIPTION_STATE_PAUSED":
      return "paused";
    case "SUBSCRIPTION_STATE_CANCELED":
      return "canceled";
    case "SUBSCRIPTION_STATE_EXPIRED":
      return "expired";
    default:
      // SUBSCRIPTION_STATE_PENDING / SUBSCRIPTION_STATE_UNSPECIFIED / unknown --
      // never grant a tier on an unrecognized state, fall back to the
      // safest option.
      return "expired";
  }
}

export interface SubscriptionV2Result {
  productId: string;
  status: InternalSubscriptionStatus;
  autoRenewing: boolean;
  expiryTime: string;
  orderId: string | null;
  obfuscatedExternalAccountId: string | null;
  acknowledged: boolean;
}

/** Fetches the current, canonical state of a subscription purchase from
 * Google -- this is the only thing either edge function trusts; the raw
 * purchase token and (for the webhook) the notification payload are never
 * trusted on their own. */
export async function fetchSubscriptionV2(
  packageName: string,
  purchaseToken: string,
  accessToken: string,
): Promise<SubscriptionV2Result> {
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${
      encodeURIComponent(packageName)
    }/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  const response = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`play_subscriptionsv2_failed:${response.status}:${text}`);
  }
  const data = JSON.parse(text) as {
    subscriptionState?: string;
    latestOrderId?: string;
    acknowledgementState?: string;
    externalAccountIdentifiers?: { obfuscatedExternalAccountId?: string };
    lineItems?: Array<{
      productId?: string;
      expiryTime?: string;
      autoRenewingPlan?: { autoRenewEnabled?: boolean };
    }>;
  };

  const lineItem = data.lineItems?.[0];
  if (!lineItem?.productId || !lineItem.expiryTime) {
    throw new Error("play_subscriptionsv2_missing_line_item");
  }

  return {
    productId: lineItem.productId,
    status: mapSubscriptionState(data.subscriptionState),
    autoRenewing: lineItem.autoRenewingPlan?.autoRenewEnabled ?? false,
    expiryTime: lineItem.expiryTime,
    orderId: data.latestOrderId ?? null,
    obfuscatedExternalAccountId: data.externalAccountIdentifiers?.obfuscatedExternalAccountId ?? null,
    acknowledged: data.acknowledgementState === "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
  };
}

/** Must happen server-side, not client-side: Play auto-refunds a purchase
 * left unacknowledged for 3 days, and since the client deliberately defers
 * completePurchase() until after server verification (see
 * BillingService.verifyAndCompletePurchase), this function -- not the
 * client -- is the one that acknowledges. Safe to call even if already
 * acknowledged in the rare race where the webhook and the initial verify
 * call overlap; Google just returns success either way. */
export async function acknowledgeSubscription(
  packageName: string,
  purchaseToken: string,
  accessToken: string,
): Promise<void> {
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${
      encodeURIComponent(packageName)
    }/purchases/subscriptions/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
  const response = await fetch(url, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({}),
  });
  if (!response.ok) {
    const text = await response.text();
    // "already acknowledged" style errors are harmless -- log and move on
    // rather than failing the whole verification over a redundant call.
    console.warn(`acknowledgeSubscription non-fatal failure: ${response.status}:${text}`);
  }
}
