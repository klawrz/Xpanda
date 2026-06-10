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

    // 2. Verify JWT and get user — pass the token explicitly (required in supabase-js v2)
    const jwt = authHeader.replace(/^Bearer\s+/i, "");

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: { user }, error: authError } = await supabase.auth.getUser(jwt);
    if (authError || !user) {
      console.error("Auth error:", authError?.message);
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
      "Rephrase the following text into a fresh version. Rules: (1) Preserve the grammatical person, voice, and tone of the original exactly — do not switch from second person to first person, or from active to passive, or change the formality level. (2) Preserve every factual claim and commitment — do not drop or weaken anything. (3) Match the word count closely — stay within 3 words of the original length. (4) Vary the wording and sentence structure so it does not sound like the previous versions. (5) Use only commas, periods, and apostrophes — no dashes of any kind. Return only the rephrased text with no explanation.";

    // 5. Call Claude
    const claudeRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-6",
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
