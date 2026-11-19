const MAX_BODY_BYTES = 16 * 1024;
const RATE_LIMIT_WINDOW_SEC = 10 * 60;
const RATE_LIMIT_MAX_REQUESTS = 5;

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const DOMAIN_RE = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9-]{2,})+$/i;

function corsHeaders(origin) {
  const allowed =
    origin === "https://www.undo.is" || origin === "http://localhost:5173"
      ? origin
      : "https://www.undo.is";

  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Cache-Control": "no-store",
  };
}

function jsonResponse(data, status, origin) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders(origin),
    },
  });
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function stripHeaderBreaks(value) {
  return String(value).replace(/[\r\n]+/g, " ").trim();
}

async function sha256Hex(value) {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function checkRateLimit(env, ip) {
  if (!env.RATE_LIMIT_KV || !ip) return { allowed: true };

  const key = `rl:${await sha256Hex(ip)}`;
  const raw = await env.RATE_LIMIT_KV.get(key);
  const count = raw ? Number.parseInt(raw, 10) || 0 : 0;

  if (count >= RATE_LIMIT_MAX_REQUESTS) {
    return { allowed: false };
  }

  await env.RATE_LIMIT_KV.put(key, String(count + 1), {
    expirationTtl: RATE_LIMIT_WINDOW_SEC,
  });

  return { allowed: true };
}

async function sendViaCloudflareEmail(env, { to, fromEmail, fromName, replyToEmail, replyToName, subject, text, html }) {
  // Prefer native Workers send_email binding when attached
  if (env.EMAIL && typeof env.EMAIL.send === "function") {
    const res = await env.EMAIL.send({
      to,
      from: { email: fromEmail, name: fromName },
      replyTo: { email: replyToEmail, name: replyToName },
      subject,
      text,
      html,
    });
    return { messageId: res?.messageId || null };
  }

  // Fallback to Cloudflare Email Sending REST API
  if (!env.CF_EMAIL_API_TOKEN || !env.CF_ACCOUNT_ID) {
    throw new Error("Email delivery is not configured yet.");
  }

  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${env.CF_ACCOUNT_ID}/email/sending/send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.CF_EMAIL_API_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        to,
        from: { address: fromEmail, name: fromName },
        reply_to: { address: replyToEmail, name: replyToName },
        subject,
        text,
        html,
      }),
    }
  );

  const result = await response.json().catch(() => ({}));
  if (!response.ok || result.success === false) {
    const errMsg = result?.errors?.[0]?.message || `Email API HTTP ${response.status}`;
    throw new Error(errMsg);
  }

  return { messageId: result?.result?.message_id || null };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin") || "";

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }

    if (url.pathname !== "/api/contact" && url.pathname !== "/api/contact/") {
      return jsonResponse({ error: "Not found" }, 404, origin);
    }

    if (request.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405, origin);
    }

    // Enforce body size cap
    const contentLength = Number.parseInt(request.headers.get("Content-Length") || "0", 10);
    if (contentLength > MAX_BODY_BYTES) {
      return jsonResponse({ error: "Request too large" }, 413, origin);
    }

    const rawBody = await request.text();
    if (rawBody.length > MAX_BODY_BYTES) {
      return jsonResponse({ error: "Request too large" }, 413, origin);
    }

    let payload;
    try {
      payload = JSON.parse(rawBody);
    } catch {
      return jsonResponse({ error: "Invalid JSON payload" }, 400, origin);
    }

    // Honeypot check: silently accept bot submissions without sending email
    if (typeof payload.website === "string" && payload.website.trim().length > 0) {
      return jsonResponse({ ok: true }, 200, origin);
    }

    const ip = request.headers.get("CF-Connecting-IP") || "";
    const rl = await checkRateLimit(env, ip);
    if (!rl.allowed) {
      return jsonResponse(
        { error: "Too many messages sent recently. Please try again in a few minutes." },
        429,
        origin
      );
    }

    const name = stripHeaderBreaks(payload.name || "");
    const email = stripHeaderBreaks(payload.email || "").toLowerCase();
    const rawSubject = stripHeaderBreaks(payload.subject || "Website Contact");
    const rawDomain = stripHeaderBreaks(payload.domain || "").toLowerCase();
    const message = String(payload.message || "").trim();

    if (!name || name.length > 100) {
      return jsonResponse({ error: "Please enter your name (max 100 characters)." }, 400, origin);
    }
    if (!email || email.length > 254 || !EMAIL_RE.test(email)) {
      return jsonResponse({ error: "Please enter a valid email address." }, 400, origin);
    }
    if (rawSubject.length > 140) {
      return jsonResponse({ error: "Subject must be 140 characters or fewer." }, 400, origin);
    }
    if (rawDomain && (rawDomain.length > 120 || !DOMAIN_RE.test(rawDomain))) {
      return jsonResponse({ error: "Invalid domain parameter." }, 400, origin);
    }
    if (message.length < 10 || message.length > 4000) {
      return jsonResponse(
        { error: "Please enter a message between 10 and 4000 characters." },
        400,
        origin
      );
    }

    const subject = rawDomain ? `[undo.is] ${rawSubject}` : `[undo.is] ${rawSubject}`;
    const to = env.TO_EMAIL || "cameron@undo.is";
    const fromEmail = env.FROM_EMAIL || "contact@undo.is";
    const fromName = "undo.is Contact Form";

    const textLines = [
      `New message from www.undo.is`,
      ``,
      `Name: ${name}`,
      `Email: ${email}`,
      ...(rawDomain ? [`Domain: ${rawDomain}`] : []),
      `Subject: ${rawSubject}`,
      ``,
      `Message:`,
      message,
    ];
    const text = textLines.join("\n");

    const html = `
      <div style="font-family: system-ui, -apple-system, sans-serif; color: #0f172a; line-height: 1.6; max-width: 640px;">
        <h2 style="margin: 0 0 12px;">New message from www.undo.is</h2>
        <p style="margin: 4px 0;"><strong>Name:</strong> ${escapeHtml(name)}</p>
        <p style="margin: 4px 0;"><strong>Email:</strong> ${escapeHtml(email)}</p>
        ${rawDomain ? `<p style="margin: 4px 0;"><strong>Domain:</strong> ${escapeHtml(rawDomain)}</p>` : ""}
        <p style="margin: 4px 0;"><strong>Subject:</strong> ${escapeHtml(rawSubject)}</p>
        <hr style="border: none; border-top: 1px solid #cbd5e1; margin: 16px 0;" />
        <p style="white-space: pre-wrap; margin: 0;">${escapeHtml(message)}</p>
      </div>
    `.trim();

    try {
      await sendViaCloudflareEmail(env, {
        to,
        fromEmail,
        fromName,
        replyToEmail: email,
        replyToName: name,
        subject,
        text,
        html,
      });

      return jsonResponse({ ok: true }, 200, origin);
    } catch (err) {
      console.error("Contact email send failed:", err?.message || err);
      return jsonResponse(
        { error: "Unable to send your message right now. Please try again later." },
        502,
        origin
      );
    }
  },
};
