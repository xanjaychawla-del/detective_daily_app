// Detective Daily — verifies a Google Play subscription purchase server-side
// and grants the corresponding tier. Called by BillingService right after
// Play reports a `purchased`/`restored` PurchaseDetails on the client.
//
// Never trusts the client alone: re-fetches the purchase's canonical state
// from the Play Developer API, confirms the purchase token actually belongs
// to the calling user (via obfuscatedExternalAccountId, set at purchase
// time from BillingService.buy's applicationUserName), and only then calls
// apply_subscription_state -- the single place any tier is ever granted on
// the strength of a purchase (also used by play-rtdn-webhook for
// renewals/cancellations).
//
// Env: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
// Secrets: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { acknowledgeSubscription, fetchSubscriptionV2, mintAccessToken } from "../_shared/google-play.ts";

const PACKAGE_NAME = "com.detectivedaily.detective_daily_app";
const VALID_PRODUCT_IDS = new Set(["lite_monthly", "premium_monthly"]);

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const serviceAccountJson = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON") ?? "";
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !serviceAccountJson) {
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  const authHeader = req.headers.get("Authorization")?.trim() ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  // Identity comes from the caller's own verified JWT, never from a
  // client-supplied id -- same pattern as delete-account.
  const authClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await authClient.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }
  const userId = userData.user.id;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_body" }, 400);
  }

  const productId = body.productId;
  const purchaseToken = body.purchaseToken;
  if (typeof productId !== "string" || !VALID_PRODUCT_IDS.has(productId)) {
    return jsonResponse({ error: "invalid_product_id" }, 400);
  }
  if (typeof purchaseToken !== "string" || !purchaseToken.trim()) {
    return jsonResponse({ error: "missing_purchase_token" }, 400);
  }

  try {
    const accessToken = await mintAccessToken(serviceAccountJson);
    const subscription = await fetchSubscriptionV2(PACKAGE_NAME, purchaseToken, accessToken);

    // The claimed product must match what Google actually has on file for
    // this token -- a client could otherwise lie about which tier a valid
    // token is for.
    if (subscription.productId !== productId) {
      return jsonResponse({ error: "product_id_mismatch" }, 400);
    }

    // This is the only thing standing between "any valid purchase token"
    // and "this specific user's purchase token" -- without it, a replayed
    // or shared token from a different account could be claimed by anyone
    // who gets hold of it.
    if (subscription.obfuscatedExternalAccountId !== userId) {
      return jsonResponse({ error: "account_mismatch" }, 403);
    }

    if (!subscription.acknowledged) {
      await acknowledgeSubscription(PACKAGE_NAME, purchaseToken, accessToken);
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);
    const { error: rpcError } = await admin.rpc("apply_subscription_state", {
      p_user_id: userId,
      p_product_id: subscription.productId,
      p_purchase_token: purchaseToken,
      p_order_id: subscription.orderId,
      p_status: subscription.status,
      p_auto_renewing: subscription.autoRenewing,
      p_expiry_time: subscription.expiryTime,
      p_notification_type: null,
    });
    if (rpcError) {
      console.error("apply_subscription_state failed:", rpcError.message);
      return jsonResponse({ error: "grant_failed", detail: rpcError.message }, 500);
    }

    const tier = subscription.productId === "premium_monthly" ? "premium" : "lite";
    return jsonResponse(
      {
        ok: true,
        tier: ["active", "in_grace_period", "on_hold"].includes(subscription.status) ? tier : "free",
        expiryTime: subscription.expiryTime,
      },
      200,
    );
  } catch (e) {
    console.error("verify-subscription-purchase failed:", e);
    return jsonResponse({ error: "verification_failed", detail: String(e) }, 502);
  }
});
