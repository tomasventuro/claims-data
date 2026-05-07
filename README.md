# Revibe Claims Dashboard

Live dashboard tracking open claims, staleness, repair partners, and cancellations.

**Live URL:** https://tomasventuro.github.io/claims-data

---

## What this is

A static HTML dashboard generated from a live MySQL query against the Revibe AP-Southeast-1 database. It is refreshed manually — whoever refreshes it runs the queries, regenerates `index.html`, and pushes to this repo. GitHub Pages serves it instantly.

---

## Repo structure

```
claims-data/
├── index.html      ← the dashboard (regenerate this on refresh)
├── queries.sql     ← all verified SQL queries used to build the dashboard
└── README.md       ← this file
```

---

## How to refresh the dashboard

**Prerequisites:**
- Claude.ai account (Pro or Team)
- DB MCP connection configured (see setup below)

**Steps:**

1. Open a new Claude chat at claude.ai
2. Say: *"Refresh the Revibe claims dashboard. Use the queries in queries.sql from github.com/tomasventuro/claims-data. Filter: claim_date > '2026-05-03' AND claim_type IS NOT NULL. Separate Golden Specialist and Platinum Repair as repair partners. White theme, widescreen layout. Verify all numbers sum to total before building."*
3. Claude will query the DB, verify all numbers, and generate a new `index.html`
4. Download the file
5. Go to github.com/tomasventuro/claims-data → click `index.html` → click pencil icon → select all → paste → commit

The dashboard is live within seconds.

---

## DB MCP setup (one-time per person)

To query the database from Claude, you need the AP-Southeast-1 MySQL MCP connection configured in your Claude account.

1. Go to **claude.ai → Settings → Integrations** (or ask your admin / Tomas for the connection details)
2. Add the MySQL MCP server pointing to the AP-Southeast-1 instance
3. Test with: `SELECT COUNT(*) FROM order_product_claims_new WHERE claim_date > '2026-05-03'` — you should get ~200+ rows

---

## Dashboard sections

| Section | What it shows |
|---|---|
| ① Pipeline by stage | All claims by stage with avg days since claim and avg days in current stage |
| ② Staleness | Open claims not updated in 24h+ and 48h+, with full list |
| ③ Claim creation | Form received deep-dive: missing docs (by document type) vs no status |
| ④ Repair partners | Golden Specialist and Platinum Repair breakdown + independent suppliers |
| ⑤ Cancelled | Breakdown by outcome (Rejected/Completed), by reason, full list |

---

## Key filters and definitions

| Thing | Definition |
|---|---|
| **Active claims filter** | `claim_date > '2026-05-03' AND claim_type IS NOT NULL AND claim_type != ''` |
| **Repair partners** | `repair_supplier_id` → `suppliers.name` IN (`Golden Specialist`, `Platinum Repair`) |
| **Independent** | Everything else (no repair partner assigned) |
| **Stale** | Open claims where `TIMESTAMPDIFF(HOUR, updated_at, NOW()) >= 24` |
| **Missing documents proxy** | `claim_documents.information_complete = 'Missing documents'` — use `missing_document` field for the type |
| **Cancellation reason** | `cancellation_reason` in `claim_cancellation_details` is not populated — use `information_complete` as proxy |

---

## Important schema notes

- **Country names**: always JOIN `countries` table on `opc.country_id` — do not use raw IDs
- **Repair partner**: use `opc.repair_supplier_id` → `suppliers.name`, NOT `original_supplier_id`
- **avg_days_in_stage**: uses different date columns per stage — see `queries.sql` query 1 for the exact CASE logic
- **Timezone**: DB stores UTC, display is UTC+4 (UAE). Use `CONVERT_TZ(field, '+00:00', '+04:00')` for display fields; WHERE filters use raw UTC

---

## Cross-check rules

Before publishing any dashboard, verify these sums match the total from query 0:

- `SUM of all stage counts` = total
- `SUM of all country counts` = total  
- `GS + Platinum + Independent` = total
- `FR missing + FR no-status + FR completed` = FR stage count
- `Cancelled sub_type sum` = cancelled stage count

Claude will do this automatically if you ask it to verify before building.

---

## Contact

Built by Tomas (Head of Operations). Questions → ping Tomas or check the query notes in `queries.sql`.
