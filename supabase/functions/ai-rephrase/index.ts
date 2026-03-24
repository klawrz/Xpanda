import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // 1. Require Authorization header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response("Unauthorized", { status: 401, headers: corsHeaders });
    }

    // 2. Verify JWT and get user via Supabase client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return new Response("Unauthorized", { status: 401, headers: corsHeaders });
    }

    // 3. Check support_safari_pro entitlement
    const { data: entitlement } = await supabase
      .from("user_entitlements")
      .select("status")
      .eq("user_id", user.id)
      .eq("entitlement_id", "support_safari_pro")
      .eq("status", "active")
      .maybeSingle();

    if (!entitlement) {
      return new Response("Subscription required", { status: 403, headers: corsHeaders });
    }

    // 4. Parse request body
    const { text, systemPrompt } = await req.json();
    if (!text) {
      return new Response("Missing text", { status: 400, headers: corsHeaders });
    }

    const effectivePrompt = systemPrompt ??
      "Rephrase the following text to add natural variety while preserving the original meaning, tone, and approximate length. Do not add explanations or notes. Return only the rephrased text.";

    // 5. Call Claude
    const claudeRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 1024,
        system: effectivePrompt,
        messages: [{ role: "user", content: text }],
      }),
    });

    if (!claudeRes.ok) {
      const err = await claudeRes.text();
      console.error("Claude error:", err);
      return new Response("AI service error", { status: 502, headers: corsHeaders });
    }

    const claudeData = await claudeRes.json();
    const result = claudeData.content?.[0]?.text;

    if (!result) {
      return new Response("Empty response from AI", { status: 502, headers: corsHeaders });
    }

    return new Response(
      JSON.stringify({ result }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err) {
    console.error("Unhandled error:", err);
    return new Response(`Error: ${err.message}`, { status: 500, headers: corsHeaders });
  }
});
