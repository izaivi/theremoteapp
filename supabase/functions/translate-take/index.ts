// supabase/functions/translate-take/index.ts
//
// Build 16: bilingual creator takes.
//
// The Flixscope app launches EN/ES. Creators (right now: Vivi — the
// founder) write a take in one language; this function fills in the other
// by calling DeepL and writing the translated column in-place. It is
// invoked by the Flutter client after insert or edit of a creator_takes
// row, and it is also safe to call manually (e.g. admin retry script).
//
// Request:   POST /functions/v1/translate-take
// Headers:   Authorization: Bearer <supabase-anon-jwt>
// Body:      { "take_id": "<uuid>", "force": false }
//
// Response (200):
//   { "ok": true, "skipped": false, "translated_to": "es" }
//   { "ok": true, "skipped": true,  "reason": "already_bilingual" }
//
// Response (4xx/5xx):
//   { "ok": false, "error": "<code>", "detail": "<message>" }
//
// Auth:  verify_jwt=true. We extract the authed user from the Authorization
//        header and require take.creator_id == user.id (403 otherwise). We
//        then do the actual DB write with the service role so the new
//        body_en/body_es columns don't need a separate RLS policy.
//
// Skip rules:
//   * Both body_en AND body_es populated and not force → skipped. Protects
//     hand-written translations (Vivi's founder takes) from being
//     overwritten when she edits one side.
//   * take is missing the source body (body_en and body_es both NULL) →
//     400, nothing to translate.
//
// DeepL source/target:
//   * Source = original_language when set (authoritative).
//   * Fallback: whichever column is populated is treated as source; if
//     both are populated the one matching original_language wins, else
//     default to EN.
//
// Secrets:
//   * DEEPL_API_KEY  (required)  — set via Supabase dashboard → Settings
//                                  → Edge Functions → Secrets.
//   * SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY — injected by default in
//                                  the Edge Runtime environment.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type Lang = "en" | "es";

interface TranslateRequest {
  take_id: string;
  force?: boolean;
}

interface CreatorTake {
  id: string;
  creator_id: string;
  body: string;
  body_en: string | null;
  body_es: string | null;
  original_language: Lang | null;
}

// DeepL free-tier endpoint. The paid tier uses api.deepl.com (no `-free`).
// Our key ends with `:fx`, which is DeepL's marker for a free-tier key, so
// we must hit the free host — sending a free key to the paid host returns
// 403 "Wrong API key type".
const DEEPL_ENDPOINT = "https://api-free.deepl.com/v2/translate";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Connection": "keep-alive",
    },
  });
}

function otherLang(src: Lang): Lang {
  return src === "en" ? "es" : "en";
}

/** Maps our internal lang code to DeepL's expected target codes. */
function deeplTarget(lang: Lang): string {
  // DeepL accepts "EN-US" or "EN-GB" for English; plain "EN" is deprecated
  // as a target. For our launch audience US English is the right pick.
  return lang === "en" ? "EN-US" : "ES";
}

function deeplSource(lang: Lang): string {
  return lang === "en" ? "EN" : "ES";
}

async function callDeepL(
  apiKey: string,
  text: string,
  source: Lang,
  target: Lang,
): Promise<string> {
  const params = new URLSearchParams();
  params.append("text", text);
  params.append("source_lang", deeplSource(source));
  params.append("target_lang", deeplTarget(target));
  // preserve_formatting keeps line breaks / punctuation — takes are short
  // editorial blurbs, we don't want DeepL "helpfully" reformatting them.
  params.append("preserve_formatting", "1");

  const res = await fetch(DEEPL_ENDPOINT, {
    method: "POST",
    headers: {
      "Authorization": `DeepL-Auth-Key ${apiKey}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });

  if (!res.ok) {
    const msg = await res.text().catch(() => "");
    throw new Error(`DeepL ${res.status}: ${msg.slice(0, 200)}`);
  }

  const data = await res.json() as {
    translations?: Array<{ text: string; detected_source_language?: string }>;
  };
  const out = data.translations?.[0]?.text;
  if (!out) throw new Error("DeepL returned empty translation");
  return out;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  // ---- env ----------------------------------------------------------------
  const deeplKey = Deno.env.get("DEEPL_API_KEY");
  const supaUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!deeplKey) {
    return json({ ok: false, error: "missing_deepl_key" }, 500);
  }
  if (!supaUrl || !serviceKey) {
    return json({ ok: false, error: "missing_supabase_env" }, 500);
  }

  // ---- parse body ---------------------------------------------------------
  let body: TranslateRequest;
  try {
    body = await req.json();
  } catch (_) {
    return json({ ok: false, error: "invalid_json" }, 400);
  }
  if (!body?.take_id || typeof body.take_id !== "string") {
    return json({ ok: false, error: "missing_take_id" }, 400);
  }
  const force = body.force === true;

  // ---- authed user --------------------------------------------------------
  // Extract user from the incoming JWT using a client scoped to that JWT.
  // The anon key is fine here; we're only using this client to read auth.
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!jwt) {
    return json({ ok: false, error: "missing_jwt" }, 401);
  }
  const userClient = createClient(supaUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userResult, error: userErr } = await userClient.auth.getUser(
    jwt,
  );
  if (userErr || !userResult?.user) {
    return json({ ok: false, error: "invalid_jwt", detail: userErr?.message }, 401);
  }
  const authedUserId = userResult.user.id;

  // ---- load take (service role bypass) ------------------------------------
  const admin = createClient(supaUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: takeRows, error: loadErr } = await admin
    .from("creator_takes")
    .select("id, creator_id, body, body_en, body_es, original_language")
    .eq("id", body.take_id)
    .limit(1);

  if (loadErr) {
    return json({ ok: false, error: "db_read_failed", detail: loadErr.message }, 500);
  }
  if (!takeRows || takeRows.length === 0) {
    return json({ ok: false, error: "take_not_found" }, 404);
  }
  const take = takeRows[0] as CreatorTake;

  // ---- authorization -------------------------------------------------------
  if (take.creator_id !== authedUserId) {
    return json({ ok: false, error: "forbidden" }, 403);
  }

  // ---- determine source / target ------------------------------------------
  const hasEn = !!take.body_en && take.body_en.trim().length > 0;
  const hasEs = !!take.body_es && take.body_es.trim().length > 0;

  if (hasEn && hasEs && !force) {
    return json({ ok: true, skipped: true, reason: "already_bilingual" });
  }

  // Decide source column:
  //   - original_language is authoritative when set AND that column is populated.
  //   - else fall back to whichever column has content.
  //   - else fall back to legacy `body` treated as EN (matches the backfill
  //     assumption: Vivi's founder takes were all authored in EN).
  let source: Lang;
  let sourceText: string;

  if (take.original_language === "en" && hasEn) {
    source = "en"; sourceText = take.body_en!;
  } else if (take.original_language === "es" && hasEs) {
    source = "es"; sourceText = take.body_es!;
  } else if (hasEn) {
    source = "en"; sourceText = take.body_en!;
  } else if (hasEs) {
    source = "es"; sourceText = take.body_es!;
  } else if (take.body && take.body.trim().length > 0) {
    source = "en"; sourceText = take.body;
  } else {
    return json({ ok: false, error: "take_has_no_body" }, 400);
  }

  const target = otherLang(source);

  // Belt-and-suspenders: if force=false and the target column is already
  // populated, don't overwrite even if original_language points the other
  // way (covers the "edited one side, translated side was manual" case).
  const targetAlreadyFilled = target === "en" ? hasEn : hasEs;
  if (targetAlreadyFilled && !force) {
    return json({ ok: true, skipped: true, reason: "target_already_filled" });
  }

  // ---- translate ----------------------------------------------------------
  let translated: string;
  try {
    translated = await callDeepL(deeplKey, sourceText, source, target);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return json({ ok: false, error: "deepl_failed", detail: msg }, 502);
  }

  // ---- write --------------------------------------------------------------
  const patch: Record<string, string> = {};
  patch[target === "en" ? "body_en" : "body_es"] = translated;

  const { error: writeErr } = await admin
    .from("creator_takes")
    .update(patch)
    .eq("id", take.id);

  if (writeErr) {
    return json(
      { ok: false, error: "db_write_failed", detail: writeErr.message },
      500,
    );
  }

  return json({
    ok: true,
    skipped: false,
    translated_to: target,
    chars: sourceText.length,
  });
});
