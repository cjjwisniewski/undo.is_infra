const STALE_AFTER_MS = 3 * 60 * 1000;

const EXPECTED_HOSTS = [
  { id: "intelligence-1", label: "intelligence-1", role: "Docker Host" },
  { id: "glados-core-1", label: "glados-core-1", role: "VM Host" },
  { id: "adventure-2", label: "adventure-2", role: "Valheim" },
  { id: "adventure-1", label: "adventure-1", role: "Minecraft" },
];

function corsHeaders(origin) {
  const allowed =
    origin === "https://www.undo.is" ||
    origin === "https://status.undo.is" ||
    origin === "http://localhost:5173"
      ? origin
      : "https://www.undo.is";

  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
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

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin") || "";

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }

    if (url.pathname === "/api/heartbeat" || url.pathname === "/api/status/heartbeat") {
      if (request.method !== "POST") {
        return jsonResponse({ error: "Method not allowed" }, 405, origin);
      }

      const auth = request.headers.get("Authorization") || "";
      if (!env.HEARTBEAT_TOKEN || auth !== `Bearer ${env.HEARTBEAT_TOKEN}`) {
        return jsonResponse({ error: "Unauthorized" }, 401, origin);
      }

      let payload;
      try {
        payload = await request.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON" }, 400, origin);
      }

      const record = {
        hosts: payload.hosts || {},
        updated_at: Date.now(),
      };

      await env.STATUS_KV.put("latest", JSON.stringify(record));
      return jsonResponse({ ok: true, updated_at: record.updated_at }, 200, origin);
    }

    if (url.pathname === "/api/status" || url.pathname === "/api/status/") {
      const raw = await env.STATUS_KV.get("latest");
      const now = Date.now();

      if (!raw) {
        return jsonResponse(
          {
            overall: "offline",
            stale: true,
            updated_at: null,
            hosts: EXPECTED_HOSTS.map((h) => ({ ...h, status: "offline", uptime: null })),
          },
          200,
          origin
        );
      }

      const data = JSON.parse(raw);
      const stale = !data.updated_at || now - data.updated_at > STALE_AFTER_MS;

      const hosts = EXPECTED_HOSTS.map((h) => {
        const reported = data.hosts?.[h.id];
        const online = !stale && reported?.status === "online";
        return {
          ...h,
          status: online ? "online" : "offline",
          uptime: online ? reported.uptime ?? null : null,
        };
      });

      const anyOnline = hosts.some((h) => h.status === "online");
      const allCoreOnline = hosts
        .filter((h) => h.id !== "adventure-1")
        .every((h) => h.status === "online");

      const overall = stale || !anyOnline ? "offline" : allCoreOnline ? "operational" : "degraded";

      return jsonResponse(
        {
          overall,
          stale,
          updated_at: data.updated_at,
          hosts,
        },
        200,
        origin
      );
    }

    if (url.hostname === "status.undo.is") {
      return Response.redirect("https://www.undo.is/status/", 302);
    }

    return jsonResponse({ error: "Not found" }, 404, origin);
  },
};
