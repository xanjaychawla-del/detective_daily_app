// Detective Daily — receives Google Play Real-time Developer Notifications
// (RTDN) via a Cloud Pub/Sub push subscription, and keeps subscription
// state (renewals, cancellations, holds, expiry, refunds) in sync.
//
// Deploy with --no-verify-jwt: Google's Pub/Sub push carries no Supabase
// user JWT at all, so the delete-account-style caller-JWT pattern doesn't
// apply here (same reason generate-case is also --no-verify-jwt).
//
// Two independent layers of trust, deliberately not relying on either
// alone:
//   1. A long random secret in the push subscription's endpoint URL
//      (?secret=...), checked first. Pragmatic for a solo-dev app --
//      verifying Pub/Sub's OIDC push token properly is a documented
//      hardening option, not required here.
//   2. The notification payload's own claims are NEVER trusted directly --
//      only the purchaseToken is extracted from it, then the current truth
//      is re-fetched from the Play Developer API and applied via the same
//      apply_subscription_state RPC verify-subscription-purchase uses. A
//      forged/duplicate notification can at worst trigger a redundant,
//      safe re-verification.
//
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, PLAY_RTDN_WEBHOOK_SECRET
// Secrets: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { fetchSubscriptionV2, mintAccessToken } from "../_shared/google-play.ts";

const PACKAGE_NAME = "com.detectivedaily.detective_daily_app";
const SUBSCRIPTION_REVOKED_NOTIFICATION_TYPE = 12;

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

interface DeveloperNotification {
  version?: string;
  packageName?: string;
  eventTimeMillis?: string;
  subscriptionNotification?: {
    version?: string;
    notificationType?: number;
    purchaseToken?: string;
    subscriptionId?: string;
  };
  testNotification?: { version?: string };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const expectedSecret = Deno.env.get("PLAY_RTDN_WEBHOOK_SECRET") ?? "";
  const suppliedSecret = new URL(req.url).searchParams.get("secret") ?? "";
  if (!expectedSecret || suppliedSecret !== expectedSecret) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const serviceAccountJson = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON") ?? "";
  if (!supabaseUrl || !serviceRoleKey || !serviceAccountJson) {
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  let pushBody: { message?: { data?: string } };
  try {
    pushBody = await req.json();
  } catch {
    // Malformed body from anything other than genuine Pub/Sub push --
    // 200 so it isn't retried forever, nothing useful to do with it.
    return jsonResponse({ ok: true, ignored: "invalid_body" }, 200);
  }

  const encodedData = pushBody.message?.data;
  if (!encodedData) {
    return jsonResponse({ ok: true, ignored: "no_message_data" }, 200);
  }

  let notification: DeveloperNotification;
  try {
    notification = JSON.parse(atob(encodedData));
  } catch {
    return jsonResponse({ ok: true, ignored: "undecodable_message_data" }, 200);
  }

  if (notification.testNotification) {
    // Play Console's "Send test notification" button -- no real purchase
    // token to act on, just confirms the endpoint is reachable.
    return jsonResponse({ ok: true, ignored: "test_notification" }, 200);
  }

  const purchaseToken = notification.subscriptionNotification?.purchaseToken;
  const notificationType = notification.subscriptionNotification?.notificationType;
  if (!purchaseToken) {
    return jsonResponse({ ok: true, ignored: "no_purchase_token" }, 200);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  // Google's push carries no Supabase identity -- this lookup is the only
  // way to find out whose subscription this is, which is exactly why
  // verify-subscription-purchase records purchase_token up front.
  const { data: existing, error: lookupError } = await admin
    .from("subscriptions")
    .select("user_id")
    .eq("purchase_token", purchaseToken)
    .maybeSingle();
  if (lookupError) {
    console.error("subscriptions lookup failed:", lookupError.message);
    return jsonResponse({ error: "lookup_failed", detail: lookupError.message }, 500);
  }
  if (!existing) {
    // A token from before this system existed, or an edge case we've never
    // seen a matching purchase for -- log and ack rather than retry
    // forever on something we structurally can't resolve.
    console.warn(`play-rtdn-webhook: no subscriptions row for purchase token (type ${notificationType})`);
    return jsonResponse({ ok: true, ignored: "unknown_purchase_token" }, 200);
  }

  try {
    const accessToken = await mintAccessToken(serviceAccountJson);
    const subscription = await fetchSubscriptionV2(PACKAGE_NAME, purchaseToken, accessToken);

    // A revoked (refunded/chargeback) purchase doesn't reliably show up as
    // a distinct subscriptionState from Google -- trust the notification
    // type for this one specific case, since it's the only source of that
    // signal at all.
    const status = notificationType === SUBSCRIPTION_REVOKED_NOTIFICATION_TYPE
      ? "revoked"
      : subscription.status;

    const { error: rpcError } = await admin.rpc("apply_subscription_state", {
      p_user_id: existing.user_id,
      p_product_id: subscription.productId,
      p_purchase_token: purchaseToken,
      p_order_id: subscription.orderId,
      p_status: status,
      p_auto_renewing: subscription.autoRenewing,
      p_expiry_time: subscription.expiryTime,
      p_notification_type: notificationType != null ? String(notificationType) : null,
    });
    if (rpcError) {
      console.error("apply_subscription_state failed:", rpcError.message);
      return jsonResponse({ error: "apply_failed", detail: rpcError.message }, 500);
    }

    return jsonResponse({ ok: true }, 200);
  } catch (e) {
    // Genuine transient failure (Google API down, DB unreachable) -- 5xx
    // so Pub/Sub retries specifically this case, unlike the "nothing to do"
    // cases above which always ack.
    console.error("play-rtdn-webhook failed:", e);
    return jsonResponse({ error: "processing_failed", detail: String(e) }, 500);
  }
});
