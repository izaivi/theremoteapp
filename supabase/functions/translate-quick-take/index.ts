// supabase/functions/translate-quick-take/index.ts
//
// Build 16: bilingual quick takes.
//
// Mirrors `translate-take` but targets `public.quick_takes`. The Flutter
// client invokes this after a quick take insert or edit to fill in the
// opposite language column via DeepL, so readers in the other UI locale
// see the take in their language instead of the original.
//
// Request:   POST /functions/v1/translate-quick-take
// Headers:   Authorization: Bearer <supabase-anon-jwt>
// Body:      { "quick_take_id": "<uuid>", "force": false }
//
// Response (200):
//   { "ok": true, "skipped": false, "translated_to": "en" }
//   { "ok": true, "skipped": true,  "reason": "already_bilingual" }
//
// Response (4xx/5xx):
//   { "ok": false, "error": "<code>", "detail": "<message>" }
//
// Auth: verify_jwt=true. The authed user must equal quick_takes.user_id
//       (403 otherwise). DB writes use the service role so the new
//       body_en/body_es columns don't need a bespoke RLS policy.
//
// Skip rules + source resolution: identical to translate-take.
//
// Secrets:
//   * DEEPL_API_KEY — required. Reused from translate-take; same
//                     Supabase secret, no separate key needed.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type Lang = "en" | "es";

interface TranslateRequest {
  quick_take_id: string;
  force?: boolean;
}

interface QuickTakeRow {
  id: string;
  user_id: string;
  body: string | null;
  body_en: string | null;
  body_es: string | null;
  original_language: Lang | null;
}

// Free-tier DeepL endpoint (our key ends in `:fx`). Paid-tier keys must
// hit api.deepl.com; mixing them returns 403 "Wrong API key type".
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

function deeplTarget(lang: Lang): string {
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
  if (!deeplKey) return json({ ok: false, error: "missing_deepl_key" }, 500);
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
  if (!body?.quick_take_id || typeof body.quick_take_id !== "string") {
    return json({ ok: false, error: "missing_quick_take_id" }, 400);
  }
  const force = body.force === true;

  // ---- authed user --------------------------------------------------------
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!jwt) return json({ ok: false, error: "missing_jwt" }, 401);

  const userClient = createClient(supaUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userResult, error: userErr } = await userClient.auth.getUser(
    jwt,
  );
  if (userErr || !userResult?.user) {
    return json(
      { ok: false, error: "invalid_jwt", detail: userErr?.message },
      401,
    );
  }
  const authedUserId = userResult.user.id;

  // ---- load quick take (service role bypass) ------------------------------
  const admin = createClient(supaUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: rows, error: loadErr } = await admin
    .from("quick_takes")
    .select("id, user_id, body, body_en, body_es, original_language")
    .eq("id", body.quick_take_id)
    .limit(1);

  if (loadErr) {
    return json(
      { ok: false, error: "db_read_failed", detail: loadErr.message },
      500,
    );
  }
  if (!rows || rows.length === 0) {
    return json({ ok: false, error: "quick_take_not_found" }, 404);
  }
  const row = rows[0] as QuickTakeRow;

  // ---- authorization ------------------------------------------------------
  // Quick takes are owned directly by user_id == auth.uid() (no creator
  // indirection). Only the author can trigger a retranslation.
  if (row.user_id !== authedUserId) {
    return json({ ok: false, error: "forbidden" }, 403);
  }

  // ---- determine source / target ------------------------------------------
  const hasEn = !!row.body_en && row.body_en.trim().length > 0;
  const hasEs = !!row.body_es && row.body_es.trim().length > 0;

  if (hasEn && hasEs && !force) {
    return json({ ok: true, skipped: true, reason: "already_bilingual" });
  }

  let source: Lang;
  let sourceText: string;

  if (row.original_language === "en" && hasEn) {
    source = "en";
    sourceText = row.body_en!;
  } else if (row.original_language === "es" && hasEs) {
    source = "es";
    sourceText = row.body_es!;
  } else if (hasEn) {
    source = "en";
    sourceText = row.body_en!;
  } else if (hasEs) {
    source = "es";
    sourceText = row.body_es!;
  } else if (row.body && row.body.trim().length > 0) {
    // Legacy row without bilingual columns. We don't know the language
    // for sure, but the migration backfill already covered the known
    // historical takes as Spanish; treat unknowns as EN here so the
    // `body` text still gets mirrored SOMEwhere.
    source = "en";
    sourceText = row.body;
  } else {
    return json({ ok: false, error: "quick_take_has_no_body" }, 400);
  }

  const target = otherLang(source);
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
    .from("quick_takes")
    .update(patch)
    .eq("id", row.id);

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
