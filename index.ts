// send-mail - drains the vendor settlement portal's outbox over SMTP.
//
// The portal never sends anything itself. It writes what it wants sent into
// vs_mail, and this runs on Supabase where the mail password can live safely.
// If this is not deployed, or the password is wrong, nothing is lost: the mail
// sits in the outbox marked queued and is visible in the app.
//
// Deploy:   supabase functions deploy send-mail --no-verify-jwt
// Secrets:  supabase secrets set SMTP_HOST=... SMTP_PORT=465 SMTP_USER=... SMTP_PASS=...
// Schedule: Supabase Dashboard -> Database -> Cron, every 5 minutes:
//             select net.http_post(
//               url    := 'https://<ref>.functions.supabase.co/send-mail',
//               headers:= '{"Authorization":"Bearer <anon key>"}'::jsonb) ;
//
// It can also be called by hand from the portal's Administration screen.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const BATCH = 25;          // per run - a settlement month is ~3 messages
const MAX_ATTEMPTS = 4;

Deno.serve(async (req) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const host = Deno.env.get("SMTP_HOST") ?? "";
  const port = Number(Deno.env.get("SMTP_PORT") ?? "465");
  const user = Deno.env.get("SMTP_USER") ?? "";
  const pass = Deno.env.get("SMTP_PASS") ?? "";

  // where the mail says it is from
  const { data: settings } = await db.from("vs_settings").select("*").eq("id", 1).single();
  const fromAddr = (Deno.env.get("SMTP_FROM") || settings?.mail_from || user || "").trim();
  const fromName = (settings?.mail_from_nm || "WeVois Vendor Settlement").trim();

  if (!host || !user || !pass || !fromAddr) {
    return json({
      ok: false,
      sent: 0,
      reason: "SMTP is not configured yet. Set SMTP_HOST, SMTP_PORT, SMTP_USER and SMTP_PASS " +
              "as function secrets, and a From address in the portal's mail settings. " +
              "The queued mail is untouched and will go out once this is done.",
    }, cors);
  }

  const { data: queue, error: qErr } = await db
    .from("vs_mail")
    .select("*")
    .eq("status", "queued")
    .lt("attempts", MAX_ATTEMPTS)
    .order("created_at", { ascending: true })
    .limit(BATCH);

  if (qErr) return json({ ok: false, error: qErr.message }, cors);
  if (!queue?.length) return json({ ok: true, sent: 0, failed: 0, note: "nothing waiting" }, cors);

  let client: SMTPClient | null = null;
  let sent = 0, failed = 0;
  const problems: string[] = [];

  try {
    client = new SMTPClient({
      connection: {
        hostname: host,
        port,
        tls: port === 465,                 // 465 implicit TLS, 587 STARTTLS
        auth: { username: user, password: pass },
      },
    });

    for (const m of queue) {
      try {
        await client.send({
          from: `${fromName} <${fromAddr}>`,
          to: m.to_name ? `${m.to_name} <${m.to_email}>` : m.to_email,
          subject: m.subject,
          content: m.body_text,
          html: m.body_html || undefined,
        });
        await db.from("vs_mail")
          .update({ status: "sent", sent_at: new Date().toISOString(), attempts: m.attempts + 1, error: "" })
          .eq("id", m.id);
        sent++;
      } catch (e) {
        const msg = String(e?.message ?? e).slice(0, 400);
        const done = m.attempts + 1 >= MAX_ATTEMPTS;
        await db.from("vs_mail")
          .update({ status: done ? "failed" : "queued", attempts: m.attempts + 1, error: msg })
          .eq("id", m.id);
        failed++;
        problems.push(`${m.to_email}: ${msg}`);
      }
    }
  } catch (e) {
    // could not even open the connection - leave everything queued, say why
    const msg = String(e?.message ?? e).slice(0, 400);
    return json({ ok: false, sent, failed, error: `SMTP connection failed: ${msg}` }, cors);
  } finally {
    try { await client?.close(); } catch { /* nothing useful to do */ }
  }

  return json({ ok: true, sent, failed, problems: problems.slice(0, 10) }, cors);
});

function json(body: unknown, cors: Record<string, string>) {
  return new Response(JSON.stringify(body, null, 2), {
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
