// Detective Daily — permanently deletes the signed-in caller's own account
// and all of their data. Required for Google Play's account-deletion
// policy (apps that support account creation must offer an in-app
// deletion path) -- this app's tier-upgrade flow supports email
// registration, so the requirement applies here too.
//
// Deletion order:
//   1. Explicit deletes for case_ratings, plays, profiles, tier_interest --
//      none of these have a declared FK back to auth.users, so nothing
//      cascades automatically.
//   2. Delete the auth.users row itself (via the admin API) -- this is
//      what actually removes the login.
//
// Env: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  const authHeader = req.headers.get("Authorization")?.trim() ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  // The caller can only ever delete their OWN account -- identity comes
  // from their own verified JWT, never from a client-supplied id.
  const authClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await authClient.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }
  const userId = userData.user.id;

  const admin = createClient(supabaseUrl, serviceRoleKey);

  const tablesToClear = ["case_ratings", "plays", "profiles", "tier_interest"];
  for (const table of tablesToClear) {
    const { error } = await admin.from(table).delete().eq("user_id", userId);
    if (error) {
      console.error(`Failed to clear ${table}:`, error.message);
      return jsonResponse({ error: "delete_failed", detail: `${table}: ${error.message}` }, 500);
    }
  }

  const { error: authDeleteError } = await admin.auth.admin.deleteUser(userId);
  if (authDeleteError) {
    console.error("Failed to delete auth user:", authDeleteError.message);
    return jsonResponse({ error: "delete_failed", detail: `auth: ${authDeleteError.message}` }, 500);
  }

  return jsonResponse({ ok: true }, 200);
});
