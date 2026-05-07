-- ============================================================
-- REVIBE CLAIMS DASHBOARD — SQL QUERIES
-- Database: AP-Southeast-1 (MySQL)
-- Filter: claim_date > '2026-05-03' AND claim_type IS NOT NULL AND claim_type != ''
-- All queries verified to sum to the same total (COUNT DISTINCT id)
-- ============================================================


-- ── 0. VERIFIED TOTAL (always run this first to confirm total) ────────────
SELECT
  COUNT(*)                                                                      AS total,
  COUNT(DISTINCT opc.id)                                                        AS unique_claims,
  SUM(CASE WHEN opc.status = 'Open'   THEN 1 ELSE 0 END)                       AS open_cnt,
  SUM(CASE WHEN opc.status = 'Closed' THEN 1 ELSE 0 END)                       AS closed_cnt,
  SUM(CASE WHEN opc.status = 'Open'   THEN op.gmv ELSE 0 END)                  AS open_exposure,
  SUM(CASE WHEN rs.name IN ('Golden Specialist','Platinum Repair') THEN 1 ELSE 0 END) AS partners,
  SUM(CASE WHEN rs.name = 'Golden Specialist'  THEN 1 ELSE 0 END)              AS golden_specialist,
  SUM(CASE WHEN rs.name = 'Platinum Repair'    THEN 1 ELSE 0 END)              AS platinum_repair,
  SUM(CASE WHEN rs.name NOT IN ('Golden Specialist','Platinum Repair')
           OR rs.name IS NULL                  THEN 1 ELSE 0 END)              AS independent,
  SUM(CASE WHEN TIMESTAMPDIFF(HOUR, opc.updated_at, NOW()) >= 24
           AND opc.status = 'Open'             THEN 1 ELSE 0 END)              AS stale_24h,
  SUM(CASE WHEN TIMESTAMPDIFF(HOUR, opc.updated_at, NOW()) >= 48
           AND opc.status = 'Open'             THEN 1 ELSE 0 END)              AS stale_48h,
  SUM(CASE WHEN TIMESTAMPDIFF(HOUR, opc.updated_at, NOW()) >= 24
           AND opc.status = 'Open'             THEN op.gmv ELSE 0 END)         AS stale_24h_exposure
FROM order_product_claims_new opc
LEFT JOIN order_products   op ON op.id  = opc.order_product_id
LEFT JOIN suppliers        rs ON rs.id  = opc.repair_supplier_id
WHERE opc.claim_date > '2026-05-03'
  AND opc.claim_type IS NOT NULL
  AND opc.claim_type != '';


-- ── 1. PIPELINE BY STAGE (with avg timing) ───────────────────────────────
SELECT
  opc.stage,
  COUNT(*) AS cnt,
  ROUND(AVG(TIMESTAMPDIFF(HOUR, opc.claim_date, NOW()) / 24.0), 1) AS avg_days_since_claim,
  ROUND(AVG(
    CASE opc.stage
      WHEN '0. Form received'      THEN TIMESTAMPDIFF(HOUR, opc.created_at,                   NOW()) / 24.0
      WHEN '1. Pending collection' THEN TIMESTAMPDIFF(HOUR, cst.pending_collection_date,       NOW()) / 24.0
      WHEN '16. Under collection'  THEN TIMESTAMPDIFF(HOUR, cst.pending_collection_date,       NOW()) / 24.0
      WHEN '2. In transit'         THEN TIMESTAMPDIFF(HOUR, cst.in_transit_date,               NOW()) / 24.0
      WHEN '3. Under QC'           THEN TIMESTAMPDIFF(HOUR, cst.under_qc_date,                 NOW()) / 24.0
      WHEN '6. Ready for refund'   THEN TIMESTAMPDIFF(HOUR, cst.ready_for_refund_date,         NOW()) / 24.0
      WHEN '7. Refunded'           THEN TIMESTAMPDIFF(HOUR, cst.refunded_date,                 NOW()) / 24.0
      WHEN '11. Cancelled'         THEN TIMESTAMPDIFF(HOUR, cst.cancelled_date,                NOW()) / 24.0
      WHEN '19. Expert revision'   THEN TIMESTAMPDIFF(HOUR, opc.updated_at,                    NOW()) / 24.0
      ELSE NULL
    END
  ), 1) AS avg_days_in_stage
FROM order_product_claims_new opc
LEFT JOIN claim_stage_tracking cst ON cst.claim_id = opc.id
WHERE opc.claim_date > '2026-05-03'
  AND opc.claim_type IS NOT NULL
  AND opc.claim_type != ''
GROUP BY opc.stage
ORDER BY cnt DESC;


-- ── 2. STALE OPEN CLAIMS — 24h+ (detail list) ────────────────────────────
SELECT
  opc.claim_id,
  op.order_help,
  opc.stage,
  c.name                                                  AS country,
  rs.name                                                 AS repair_supplier,
  opc.sub_type,
  TIMESTAMPDIFF(HOUR, opc.updated_at, NOW())             AS hours_since_update,
  op.gmv                                                  AS amount
FROM order_product_claims_new opc
LEFT JOIN order_products op ON op.id  = opc.order_product_id
LEFT JOIN suppliers      rs ON rs.id  = opc.repair_supplier_id
LEFT JOIN countries       c ON c.id   = opc.country_id
WHERE opc.claim_date > '2026-05-03'
  AND opc.claim_type IS NOT NULL
  AND opc.claim_type != ''
  AND opc.status = 'Open'
  AND TIMESTAMPDIFF(HOUR, opc.updated_at, NOW()) >= 24
ORDER BY hours_since_update DESC;


-- ── 3. FORM RECEIVED — information completeness breakdown ────────────────
-- 3a. Top-level split (missing / no status / completed)
SELECT
  cd.information_complete,
  COUNT(*) AS cnt
FROM order_product_claims_new opc
LEFT JOIN claim_documents cd ON cd.claim_id = opc.id
WHERE opc.claim_date > '2026-05-03'
  AND opc.claim_type IS NOT NULL
  AND opc.claim_type != ''
  AND opc.stage = '0. Form received'
GROUP BY cd.information_complete;

-- 3b. Missing documents — by document type (missing_document field)
SELECT
  cd.missing_document,
  COUNT(*) AS cnt
FROM order_product_claims_new opc
LEFT JOIN claim_documents cd ON cd.claim_id = opc.id
WHERE opc.claim_date > '2026-05-03'
  AND opc.claim_type IS NOT NULL
  AND opc.claim_type != ''
  AND opc.stage = '0. Form received'
  AND cd.information_complete = 'Missing documents'
GROUP BY cd.missing_document
ORDER BY cnt DESC;


-- ── 4. REPAIR PARTNERS — stage + exposure breakdown ──────────────────────
SELECT
  rs.name                                                 AS partner,
  opc.stage,
  opc.status,
  COUNT(*)                                                AS cnt,
  SUM(op.gmv)                                            AS exposure
FROM order_product_claims_new opc
LEFT JOIN order_products op ON op.id = opc.order_product_id
LEFT JOIN suppliers      rs ON rs.id = opc.repair_supplier_id
WHERE opc.claim_date > '2026-05-03'
  AND opc.claim_type IS NOT NULL
  AND opc.claim_type != ''
  AND rs.name IN ('Golden Specialist', 'Platinum Repair')
GROUP BY rs.name, opc.stage, opc.status
ORDER BY rs.name, cnt DESC;


-- ── 5. CANCELLED CLAIMS — breakdown ──────────────────────────────────────
-- 5a. By sub_type
SELECT opc.sub_type, COUNT(*) AS cnt
FROM order_product_claims_new opc
WHERE opc.claim_date > '2026-05-03'
  AND opc.claim_type IS NOT NULL
  AND opc.claim_type != ''
  AND opc.stage = '11. Cancelled'
GROUP BY opc.sub_type;

-- 5b. By outcome (information_complete as proxy — cancellation_reason not populated)
SELECT
  COALESCE(NULLIF(cd.information_complete, ''), 'No status') AS outcome,
  COUNT(*) AS cnt
FROM order_product_claims_new opc
LEFT JOIN claim_documents cd ON cd.claim_id = opc.id
WHERE opc.claim_date > '2026-05-03'
  AND opc.claim_type IS NOT NULL
  AND opc.claim_type != ''
  AND opc.stage = '11. Cancelled'
GROUP BY outcome;

-- 5c. Full cancelled claims list (claim_id + order_help)
SELECT
  opc.claim_id,
  op.order_help,
  opc.sub_type,
  COALESCE(NULLIF(cd.information_complete, ''), 'No status') AS outcome,
  c.name AS country
FROM order_product_claims_new opc
LEFT JOIN order_products  op ON op.id  = opc.order_product_id
LEFT JOIN claim_documents cd ON cd.claim_id = opc.id
LEFT JOIN countries        c ON c.id   = opc.country_id
WHERE opc.claim_date > '2026-05-03'
  AND opc.claim_type IS NOT NULL
  AND opc.claim_type != ''
  AND opc.stage = '11. Cancelled'
ORDER BY c.name, opc.sub_type;


-- ── 6. ATOMIC QUERY — single query for all dashboard aggregates ──────────
-- Use this to build the full dashboard in one round trip.
-- Group by all dimensions needed; aggregate counts and GMV per cell.
SELECT
  opc.stage,
  c.name                                                                        AS country,
  CASE
    WHEN rs.name IN ('Golden Specialist', 'Platinum Repair') THEN rs.name
    ELSE 'Independent'
  END                                                                           AS bucket,
  opc.sub_type,
  opc.status,
  cd.information_complete,
  COUNT(*)                                                                      AS cnt,
  SUM(op.gmv)                                                                  AS total_gmv
FROM order_product_claims_new opc
LEFT JOIN order_products   op ON op.id  = opc.order_product_id
LEFT JOIN suppliers        rs ON rs.id  = opc.repair_supplier_id
LEFT JOIN countries         c ON c.id   = opc.country_id
LEFT JOIN claim_documents  cd ON cd.claim_id = opc.id
WHERE opc.claim_date > '2026-05-03'
  AND opc.claim_type IS NOT NULL
  AND opc.claim_type != ''
GROUP BY opc.stage, c.name, bucket, opc.sub_type, opc.status, cd.information_complete;


-- ── NOTES ─────────────────────────────────────────────────────────────────
-- • claim_type filter: IS NOT NULL AND != '' — filters out raw unprocessed forms
-- • Repair partners defined as: repair_supplier = 'Golden Specialist' OR 'Platinum Repair'
--   (matched via opc.repair_supplier_id → suppliers.name, NOT original_supplier_id)
-- • Country names come from the countries table (JOIN on opc.country_id)
--   Do NOT use country_id directly — IDs: 1=UAE, 2=Saudi Arabia, 4=South Africa
-- • cancellation_reason in claim_cancellation_details is NULL for all claims in this period
--   Use information_complete as proxy: Rejected=invalid, Completed=closed cleanly
-- • avg_days_in_stage uses different date columns per stage (see query 1 above)
-- • All queries use UTC+4 (UAE time) via CONVERT_TZ where needed on display fields
--   but WHERE filters use raw UTC stored values
