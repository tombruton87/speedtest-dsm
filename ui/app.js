// Speedtest Tracker's tabs on the chassis window: Speed, Schedule, Alerts, Account, and the HTTPS part of Site address.
(function (P) {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var EVERY = { "1h": "every hour", "3h": "every 3 hours", "6h": "every 6 hours", "12h": "twice a day", "24h": "once a day", "off": "only when you ask" };
  function stUrl(st) { return ((st.app || {}).url || "").replace(/\/$/, ""); }
  function mbps(b) { return b == null ? "–" : (b / 1e6 >= 100 ? Math.round(b / 1e6) : (b / 1e6).toFixed(1)) + " Mbps"; }
  function ms(v) { return v == null ? "–" : v + " ms"; }
  function touched(id) { ["input", "change"].forEach(function (e) { $(id).addEventListener(e, function () { $(id).dataset.touched = "1"; }); }); }
  function quiet(id, v) { if (!$(id).dataset.touched) { if ($(id).type === "checkbox") $(id).checked = !!v; else $(id).value = v == null ? "" : v; } }
  function links(st) { document.querySelectorAll(".st-link").forEach(function (x) { x.href = stUrl(st) ? stUrl(st) + (x.dataset.path || "") : "#"; }); }
  function num(v) { var n = parseInt(v, 10); return isNaN(n) || n < 0 ? 0 : n; }

  // ---------------------------------------------------------------- Speed
  P.register("speed", {
    render: function (st) {
      var a = st.app || {}, rec = a.recent || [], last = rec.filter(function (r) { return r.status === "completed"; })[0], t = $("sp-tiles"), avg = a.avg || {};
      links(st); $("hs-dir").textContent = (a.history || {}).dir || "Speed history";
      P.clear(t);
      P.tile(t, last ? mbps(last.down) : "–", "download, latest"); P.tile(t, last ? mbps(last.up) : "–", "upload"); P.tile(t, last ? ms(last.ping) : "–", "ping");
      P.tile(t, (avg.d7 || {}).n ? mbps(avg.d7.down) : "–", "download, 7-day average");
      $("sp-run").disabled = !!a.running || P.busy || !a.up;
      var s = $("sp-state"); P.clear(s);
      if (a.running) { var r = P.el("span", null, "st-run"); r.appendChild(P.el("span", null, "st-dot")); r.appendChild(document.createTextNode("A test is running — about half a minute.")); s.appendChild(r); }
      else s.textContent = (last ? "Last test " + P.ago(last.at) + ". " : "No tests yet. ") + "Tests run " + (EVERY[a.every] || a.every || "") + (a.every === "off" ? "" : " by themselves") + ".";
      var ta = $("sp-avg"); P.clear(ta);
      [["Last 24 hours", avg.d1], ["Last 7 days", avg.d7], ["Last 30 days", avg.d30]].forEach(function (p) {
        var v = p[1] || {}; P.row(ta, [p[0], String(v.n || 0), v.n ? mbps(v.down) : "–", v.n ? mbps(v.up) : "–", v.n ? ms(v.ping) : "–"]);
      });
      var tb = $("sp-recent"), sig = JSON.stringify(rec); if (tb.dataset.sig === sig) return; tb.dataset.sig = sig; P.clear(tb);
      if (!rec.length) { var r0 = P.el("tr"), c0 = P.cell("No results yet: press Test now, or wait for the schedule.", "empty"); c0.colSpan = 6; r0.appendChild(c0); tb.appendChild(r0); }
      rec.forEach(function (r) {
        var when = P.el("div"); when.appendChild(document.createTextNode(r.at ? P.ago(r.at) : "–"));
        if (!r.scheduled) when.appendChild(P.el("div", "asked for", "muted small"));
        var chip = r.status === "failed" ? P.chip("failed", "bad") : r.status !== "completed" ? P.chip(r.status, "") : r.healthy === false ? P.chip("below thresholds", "warn") : r.healthy === true ? P.chip("good", "ok") : P.el("span", "");
        var server = P.el("div"); server.appendChild(document.createTextNode(r.status === "failed" ? (r.message || "") : (r.server || "–")));
        if (r.isp && r.status !== "failed") server.appendChild(P.el("div", r.isp, "muted small"));
        var cells = [P.cell(when), P.cell(P.el("span", r.status === "completed" ? mbps(r.down) : "–", "st-num")), P.cell(P.el("span", r.status === "completed" ? mbps(r.up) : "–", "st-num")),
                     P.cell(P.el("span", r.status === "completed" ? ms(r.ping) : "–", "st-num")), P.cell(server), P.cell(chip, "n")];
        var tr = P.row(tb, cells); if (r.status === "failed") tr.className = "muted-row";
      });
      $("hs-at").textContent = (a.history || {}).at ? "Last written " + P.ago(a.history.at) + "." : "";
    },
    tiles: function (t, st) { var r = ((st.app || {}).recent || []).filter(function (x) { return x.status === "completed"; })[0]; P.tile(t, r ? mbps(r.down) : "–", "download, latest"); }
  });
  $("sp-run").onclick = function () { P.act("runnow", {}); };

  // ---------------------------------------------------------------- Schedule
  ["sc-every", "sc-server", "sc-keep"].forEach(touched);
  P.register("schedule", {
    render: function (st) {
      var a = st.app || {}, sel = $("sc-server"), list = a.servers || [], want = a.server || "";
      var sig = JSON.stringify(list) + "|" + want;
      if (sel.dataset.sig !== sig && !sel.dataset.touched) {
        sel.dataset.sig = sig; while (sel.options.length > 1) sel.remove(1);
        list.forEach(function (s) { var o = document.createElement("option"); o.value = String(s.id); o.textContent = s.name + " — " + s.location + (s.country ? ", " + s.country : ""); sel.appendChild(o); });
        if (want && !list.some(function (s) { return String(s.id) === String(want); })) { var o = document.createElement("option"); o.value = want; o.textContent = "Server " + want; sel.appendChild(o); }
      }
      quiet("sc-every", a.every || "6h"); quiet("sc-server", want); quiet("sc-keep", String(a.keep || 0));
      $("sc-cron").textContent = a.cron ? "As cron: " + a.cron + " — at " + a.cron.split(" ")[0] + " minutes past, so this Synology doesn't test at the same moment as everyone else's." : "";
      var s = $("pb-state"), b = $("pb-btn"); P.clear(s); P.clear(b);
      s.appendChild(a.public ? P.chip("public", "warn") : P.chip("sign-in needed", "ok"));
      b.appendChild(P.btn(a.public ? "Require a sign-in" : "Make it public", "", function () { P.act("public", { on: a.public ? 0 : 1 }, a.public ? null : "Show the dashboard to anyone who can reach Speedtest Tracker, without a sign-in?"); }));
    }
  });
  $("sc-find").onclick = function (e) { e.preventDefault(); P.act("servers", {}); };
  $("sc-save").onclick = function () {
    P.act("schedule", { every: $("sc-every").value, server: $("sc-server").value, keep: $("sc-keep").value })
      .then(function () { ["sc-every", "sc-server", "sc-keep"].forEach(function (id) { $(id).dataset.touched = ""; }); });
  };

  // ---------------------------------------------------------------- Alerts
  ["al-on", "al-down", "al-up", "al-ping"].forEach(touched);
  P.register("alerts", {
    render: function (st) {
      var a = st.app || {}, l = a.limits || {}, rec = a.recent || [], t = $("al-tiles");
      quiet("al-on", l.on); quiet("al-down", l.down ? Math.round(l.down) : ""); quiet("al-up", l.up ? Math.round(l.up) : ""); quiet("al-ping", l.ping ? Math.round(l.ping) : "");
      P.clear(t);
      P.tile(t, l.on ? "on" : "off", "thresholds");
      P.tile(t, String(rec.filter(function (r) { return r.healthy === false; }).length), "of the latest " + rec.length + " below them");
      P.tile(t, String(a.failed7 || 0), "failed tests, 7 days");
      var s = $("al-dsm"), b = $("al-dsm-btn"); P.clear(s); P.clear(b);
      s.appendChild(a.alerts ? P.chip("on", "ok") : P.chip("off", ""));
      b.appendChild(P.btn(a.alerts ? "Turn off" : "Turn on", "", function () { P.act("alerts", { on: a.alerts ? 0 : 1 }); }));
    }
  });
  $("al-save").onclick = function () {
    P.act("limits", { on: $("al-on").checked ? 1 : 0, down: num($("al-down").value), up: num($("al-up").value), ping: num($("al-ping").value) })
      .then(function () { ["al-on", "al-down", "al-up", "al-ping"].forEach(function (id) { $(id).dataset.touched = ""; }); });
  };

  // ---------------------------------------------------------------- Account
  P.register("account", {
    render: function (st) {
      var a = st.app || {}, me = a.me || {}, tb = $("ac-me"); P.clear(tb);
      P.kv(tb, "Name", me.name || "–"); P.kv(tb, "Email (sign-in)", me.email || "–");
      $("tk-api").textContent = (stUrl(st) || "") + "/api/v1/results/latest";
      var tt = $("ac-tokens"), toks = a.tokens || [], sig = JSON.stringify(toks) + "|" + P.busy + "|" + P.role; if (tt.dataset.sig === sig) return; tt.dataset.sig = sig; P.clear(tt);
      if (!toks.length) { var r0 = P.el("tr"), c0 = P.cell("No tokens yet.", "empty"); c0.colSpan = 5; r0.appendChild(c0); tt.appendChild(r0); }
      toks.forEach(function (k) {
        var may = (k.abilities || []).indexOf("speedtests:run") >= 0 ? "read, start tests" : "read";
        P.row(tt, [k.name, may, k.created ? P.ago(k.created) : "–", k.used ? P.ago(k.used) : "never",
          P.cell(P.btn("Remove", "danger", function () { P.act("untoken", { id: k.id }, "Remove the token " + k.name + "? Whatever uses it stops working."); }), "n")]);
      });
    }
  });
  P.register("secretNote", function (s) { return /^API token/.test(s.email || "") ? "Paste it into the app that needs it now: it isn't kept anywhere you can see it again." : "Use it to sign in to Speedtest Tracker, then keep it in your password manager."; });
  $("tk-add").onclick = function () { P.act("token", { name: $("tk-name").value.trim(), kind: $("tk-kind").value }).then(function () { $("tk-name").value = ""; }); };

  // ---------------------------------------------------------------- Site address: HTTPS
  P.register("site", {
    fill: function (st) { var t = (st.app && st.app.tls) || {}; $("set-tls").value = t.mode || "off"; },
    values: function () { return { tls: $("set-tls").value }; },
    render: function (st) {
      var t = (st.app && st.app.tls) || {}, c = t.cert, tb = $("tls-info"), note = $("tls-note"), acts = $("tls-actions"); P.clear(tb); P.clear(acts);
      $("tls-card").hidden = !t.mode || t.mode === "off";
      if (!t.mode || t.mode === "off") return;
      if (!c) { P.kv(tb, "Certificate", "none yet — it's made or read when Speedtest Tracker starts"); note.textContent = ""; return; }
      P.kv(tb, "From", t.source === "dsm" ? "DSM (the system default certificate)" : "the package (self-signed)");
      P.kv(tb, "Issued to", c.subject || "–"); P.kv(tb, "Issued by", c.self_signed ? "itself (self-signed)" : (c.issuer || "–"));
      P.kv(tb, "Expires", (c.expires || "–") + (typeof c.days_left === "number" ? " (" + (c.days_left < 0 ? "expired" : c.days_left + " days") + ")" : ""));
      if (c.names) P.kv(tb, "Names", c.names.replace(/,/g, ", "));
      note.textContent = t.mode === "dsm" && t.source === "self" ? "DSM's certificate wasn't found on this system, so a self-signed one is in use."
        : c.self_signed ? "Self-signed: browsers warn once. For no warning, use a trusted certificate (Let's Encrypt in DSM, made the system default)."
        : "Browsers trust this certificate as long as they reach Speedtest Tracker by one of its names.";
      acts.appendChild(P.btn(t.mode === "dsm" ? "Read DSM's certificate again" : "Make a new self-signed certificate", "", function () { P.act("refreshcert", {}, t.mode === "dsm" ? null : "Make a new self-signed certificate?"); }));
    }
  });
  $("set-tls").addEventListener("change", function () { $("set-url").dataset.touched = "1"; var u = $("set-url").value.trim(); if ($("set-tls").value !== "off" && /^http:\/\//.test(u)) $("set-url").value = "https://" + u.slice(7); });

  // ---------------------------------------------------------------- Storage
  P.register("storage", { render: function (app, st, box) {
    P.clear(box); var c = P.el("div", null, "card"); c.appendChild(P.el("h2", "Speedtest Tracker's data")); var tbl = P.el("table"), tb = P.el("tbody"); tbl.appendChild(tb); c.appendChild(tbl);
    [["Results database (SQLite)", app.database], ["Logs", app.logs], ["Speed history (CSV, in the shared folder)", app.history]].forEach(function (p) { P.kv(tb, p[0], P.mb(p[1] || 0), true); });
    box.appendChild(c);
  } });
})(window.Panel);
