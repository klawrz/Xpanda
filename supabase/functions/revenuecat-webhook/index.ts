import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Events that mean the subscription is active
const ACTIVE_EVENTS = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "PRODUCT_CHANGE",
  "TRANSFER",
]);

// Events that mean the subscription is no longer active
const INACTIVE_EVENTS = new Set([
  "EXPIRATION",
  "SUBSCRIBER_ALIAS",
]);

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Verify RevenueCat webhook authorization
  const authHeader = req.headers.get("Authorization");
  const webhookSecret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  if (webhookSecret && authHeader !== webhookSecret) {
    console.error("Webhook auth failed");
    return new Response("Unauthorized", { status: 401 });
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const event = body?.event;
  if (!event) {
    return new Response("Missing event", { status: 400 });
  }

  const eventType: string = event.type;
  const appUserID: string = event.app_user_id;
  const entitlementID = "xpanda";

  if (!appUserID) {
    return new Response("Missing app_user_id", { status: 400 });
  }

  console.log();

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  if (ACTIVE_EVENTS.has(eventType)) {
    // Upsert active entitlement
    const expiresAt = event.expiration_at_ms
      ? new Date(event.expiration_at_ms).toISOString()
      : null;

    const { error } = await supabase
      .from("user_entitlements")
      .upsert({
        user_id: appUserID,
        entitlement_id: entitlementID,
        status: "active",
        expires_at: expiresAt,
        source: "revenuecat",
      }, { onConflict: "user_id,entitlement_id" });

    if (error) {
      console.error("Upsert error:", error);
      return new Response("DB error", { status: 500 });
    }

    console.log();

  } else if (INACTIVE_EVENTS.has(eventType)) {
    // Mark entitlement as inactive
    const { error } = await supabase
      .from("user_entitlements")
      .update({ status: "inactive", expires_at: new Date().toISOString() })
      .eq("user_id", appUserID)
      .eq("entitlement_id", entitlementID);

    if (error) {
      console.error("Update error:", error);
      return new Response("DB error", { status: 500 });
    }

    console.log();

  } else {
    // CANCELLATION, BILLING_ISSUE etc — log but keep access until expiration
    console.log();
  }

  return new Response("OK", { status: 200 });
});
