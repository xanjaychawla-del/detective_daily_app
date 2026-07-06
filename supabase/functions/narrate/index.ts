// AI Adapter endpoint: takes exactly one Truth Engine fact plus enough
// persona/context to phrase it naturally, and returns only that phrasing.
// It is never given the full case file and can't invent new facts.
//
// Replaces the local dev-only proxy (server/index.js), which only a device
// on the same network as the developer's machine (or an Android emulator,
// via its 10.0.2.2 loopback alias) could ever reach -- a real phone on
// another network would hang for the full client-side timeout on every
// line of dialogue before falling back to unnarrated text.
//
// Secrets: GEMINI_API_KEY
// Deploy with --no-verify-jwt, matching generate-case (see that function's
// header comment for why -- same no-real-auth-yet rationale).

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const MODEL = "gemini-2.5-flash";

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

interface HistoryTurn {
  role?: string;
  text?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  const body = await req.json().catch(() => null);
  const suspectName = body?.suspectName;
  const persona = body?.persona;
  const fact = body?.fact;
  const category = body?.category;
  const history = body?.history;

  if (typeof fact !== "string" || !fact.trim()) {
    return jsonResponse({ error: "missing_fact" }, 400);
  }
  if (typeof suspectName !== "string" || !suspectName.trim()) {
    return jsonResponse({ error: "missing_suspect" }, 400);
  }

  const systemPrompt =
    `You are voicing ONE character, ${suspectName}, who is being interviewed as a suspect in a detective mystery game.

Persona: ${persona || "A person being questioned in a mystery investigation."}

STRICT RULES:
- Phrase ONLY the single fact given below, in character. Do not invent any new facts, names, times, evidence, or details that are not present in the fact.
- Do not add new claims about guilt or innocence, and do not confirm or deny being responsible for anything -- that is not something this character would know to signal one way or the other.
- Keep it to 1-4 sentences of natural spoken dialogue. No stage directions, no quotation marks, no narration -- just what the character says out loud.
- Stay consistent with the persona's tone across the conversation.

The fact to phrase (do not add to or deviate from its content):
"""
${fact.trim()}
"""`;

  const priorTurns: HistoryTurn[] = Array.isArray(history) ? history.slice(-6) : [];
  const contents = priorTurns.map((turn) => ({
    role: turn?.role === "suspect" ? "model" : "user",
    parts: [{ text: String(turn?.text ?? "") }],
  }));
  contents.push({
    role: "user",
    parts: [{ text: `Category: ${category || "general"}. Say the fact above, in character, now.` }],
  });

  const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`;

  try {
    const response = await fetch(geminiUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: systemPrompt }] },
        contents,
        generationConfig: {
          temperature: 0.9,
          maxOutputTokens: 200,
          thinkingConfig: { thinkingBudget: 0 },
        },
      }),
    });

    const raw = await response.text();
    if (!response.ok) {
      console.error("Gemini upstream error:", response.status, raw);
      return jsonResponse({ error: "upstream_error" }, 502);
    }

    let reply: string;
    try {
      const outer = JSON.parse(raw);
      const text = outer.candidates?.[0]?.content?.parts?.[0]?.text;
      if (!text) throw new Error("empty_gemini_text");
      reply = text.trim();
    } catch (parseErr) {
      console.error("Gemini parse failed:", parseErr, raw);
      return jsonResponse({ error: "parse_failed" }, 502);
    }

    return jsonResponse({ reply }, 200);
  } catch (err) {
    console.error("Gemini error:", (err as Error)?.message ?? err);
    return jsonResponse({ error: "upstream_error" }, 502);
  }
});
