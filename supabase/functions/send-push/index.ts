// StayVB — send-push Edge Function
// Salje web push notifikaciju svim (ili partner-filtriranim) pretplatnicima.
// Poziva se samo iz admin panela, sa authenticated (admin) sesijom.
//
// Potrebni secrets (Dashboard -> Edge Functions -> send-push -> Secrets):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY su vec
// automatski dostupni u svakoj Edge Function-u, ne treba ih rucno dodavati.

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY")!;
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY")!;
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") || "mailto:admin@staytag.rs";

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    // Proveri da je pozivalac stvarno ulogovan admin (ne samo bilo koji
    // authenticated JWT — platforma to vec proverava, ovo je dodatni sloj
    // dosledan is_admin() modelu iz baze).
    const authHeader = req.headers.get("Authorization") || "";
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user?.email) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: corsHeaders });
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const { data: isAdminRow } = await admin
      .from("admin_users")
      .select("email")
      .eq("email", userData.user.email)
      .maybeSingle();
    if (!isAdminRow) {
      return new Response(JSON.stringify({ error: "Forbidden" }), { status: 403, headers: corsHeaders });
    }

    const { title, body, url, partner_code } = await req.json();
    if (!title || !body) {
      return new Response(JSON.stringify({ error: "title i body su obavezni" }), { status: 400, headers: corsHeaders });
    }

    let query = admin.from("push_subscriptions").select("id, endpoint, p256dh, auth, partner_code");
    if (partner_code) query = query.eq("partner_code", partner_code);
    const { data: subs, error: subsErr } = await query;
    if (subsErr) throw subsErr;

    const payload = JSON.stringify({ title, body, url: url || "./" });
    let sent = 0;
    const staleIds: string[] = [];

    await Promise.all((subs || []).map(async (s) => {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          payload
        );
        sent++;
      } catch (err) {
        const status = (err as { statusCode?: number })?.statusCode;
        if (status === 404 || status === 410) {
          staleIds.push(s.id as string);
        } else {
          console.error("push send error", s.endpoint, err);
        }
      }
    }));

    if (staleIds.length) {
      await admin.from("push_subscriptions").delete().in("id", staleIds);
    }

    await admin.from("push_notifications_log").insert({
      partner_code: partner_code || null,
      type: "admin_broadcast",
      title,
      body,
      sent_count: sent,
    });

    return new Response(
      JSON.stringify({ ok: true, sent, total: (subs || []).length, removed_stale: staleIds.length }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: String((e as Error)?.message || e) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});
