require('dotenv').config();

const express = require('express');
const cors = require('cors');

const apiKey = process.env.GEMINI_API_KEY;
const MODEL = process.env.GEMINI_MODEL || 'gemini-2.5-flash';

const app = express();
app.use(cors());
app.use(express.json());

app.get('/health', (_req, res) => res.json({ ok: true, configured: Boolean(apiKey) }));

// The AI Adapter endpoint: takes exactly one Truth Engine fact plus enough
// persona/context to phrase it naturally, and returns only that phrasing.
// It is never given the full case file and can't invent new facts.
app.post('/api/narrate', async (req, res) => {
  if (!apiKey) {
    return res.status(500).json({ error: 'server_misconfigured' });
  }

  const { suspectName, persona, fact, category, history } = req.body ?? {};
  if (typeof fact !== 'string' || !fact.trim()) {
    return res.status(400).json({ error: 'missing_fact' });
  }
  if (typeof suspectName !== 'string' || !suspectName.trim()) {
    return res.status(400).json({ error: 'missing_suspect' });
  }

  const systemPrompt = `You are voicing ONE character, ${suspectName}, who is being interviewed as a suspect in a detective mystery game.

Persona: ${persona || 'A person being questioned in a mystery investigation.'}

STRICT RULES:
- Phrase ONLY the single fact given below, in character. Do not invent any new facts, names, times, evidence, or details that are not present in the fact.
- Do not add new claims about guilt or innocence, and do not confirm or deny being responsible for anything -- that is not something this character would know to signal one way or the other.
- Keep it to 1-4 sentences of natural spoken dialogue. No stage directions, no quotation marks, no narration -- just what the character says out loud.
- Stay consistent with the persona's tone across the conversation.

The fact to phrase (do not add to or deviate from its content):
"""
${fact.trim()}
"""`;

  const priorTurns = Array.isArray(history) ? history.slice(-6) : [];
  const contents = priorTurns.map((turn) => ({
    role: turn && turn.role === 'suspect' ? 'model' : 'user',
    parts: [{ text: String((turn && turn.text) || '') }],
  }));
  contents.push({
    role: 'user',
    parts: [{ text: `Category: ${category || 'general'}. Say the fact above, in character, now.` }],
  });

  const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${apiKey}`;

  try {
    const response = await fetch(geminiUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
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
      console.error('Gemini upstream error:', response.status, raw);
      return res.status(502).json({ error: 'upstream_error' });
    }

    let reply;
    try {
      const outer = JSON.parse(raw);
      const text = outer.candidates?.[0]?.content?.parts?.[0]?.text;
      if (!text) throw new Error('empty_gemini_text');
      reply = text.trim();
    } catch (parseErr) {
      console.error('Gemini parse failed:', parseErr, raw);
      return res.status(502).json({ error: 'parse_failed' });
    }

    res.json({ reply });
  } catch (err) {
    console.error('Gemini error:', err?.message || err);
    res.status(502).json({ error: 'upstream_error' });
  }
});

const port = process.env.PORT || 8787;
app.listen(port, () => {
  console.log(`Detective Daily narration proxy listening on http://localhost:${port}`);
  if (!apiKey) {
    console.warn('GEMINI_API_KEY is not set -- /api/narrate will return server_misconfigured until it is.');
  }
});
