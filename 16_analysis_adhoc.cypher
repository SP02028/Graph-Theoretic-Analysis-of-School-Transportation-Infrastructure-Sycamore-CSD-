// ════════════════════════════════════════════════════════════════════════
// 16_analysis_adhoc.cypher
// Ad-hoc analysis queries used during the centrality research session.
// All READ ONLY. Safe to run at any time on a healthy graph.
//
// Covers:
//   A. Full health check
//   B. Bridge exposure ranked
//   C. Route path traversal
//   D. T1-CRITICAL bridge neighbors
//   E. Unprotected route identification
//   F. Node isolation checks
//   G. Bypass coverage by bridge
// ════════════════════════════════════════════════════════════════════════

// ── A. Full health check ──────────────────────────────────────────────────
// Expected: nodes=221  primary=545  alt=202  health=PASS
MATCH (n) WITH count(n) AS nodes
MATCH ()-[r:ROAD_SEGMENT]->() WHERE r.altRoute = false
WITH nodes, count(r) AS primary
MATCH ()-[r2:ROAD_SEGMENT]->() WHERE r2.altRoute = true
WITH nodes, primary, count(r2) AS alt
RETURN nodes, primary, alt, (primary + alt) AS total_edges,
       CASE WHEN nodes = 221 AND primary = 545 AND alt = 202
            THEN 'PASS' ELSE 'FAIL' END AS health;

// ── B. Bridge route exposure ranked ───────────────────────────────────────
// Expected top 3: BRG_COOPER_I71=36, BRG_MONTGOMERY_CREEK=30,
//                 BRG_KENWOOD_CREEK=23
MATCH ()-[r:ROAD_SEGMENT {altRoute: false}]->(b:Bridge)
RETURN b.id, b.tier,
       count(DISTINCT r.routeId) AS primary_routes
ORDER BY primary_routes DESC;

// ── C. Sample route end-to-end (Kenwood) ──────────────────────────────────
// Traces the full primary path of RD_KENWOOD from NBH to SJH.
MATCH p = (nbh:Neighborhood)-[:ROAD_SEGMENT*]->(s:School {id: 'SJH'})
WHERE ALL(r IN relationships(p)
          WHERE r.routeId = 'RD_KENWOOD' AND r.altRoute = false)
RETURN [n IN nodes(p) | n.id] AS path, length(p) AS hops
LIMIT 1;

// ── D. T1-CRITICAL bridge neighbors ───────────────────────────────────────
// Shows direct upstream and downstream nodes for both T1 bridges.
MATCH (b:Bridge) WHERE b.tier = 'T1-CRITICAL'
MATCH (up)-[:ROAD_SEGMENT]->(b)-[:ROAD_SEGMENT]->(dn)
RETURN b.id, b.name,
       collect(DISTINCT up.id) AS upstream_nodes,
       collect(DISTINCT dn.id) AS downstream_nodes;

// ── E. All unprotected routes per bridge ──────────────────────────────────
// For each bridge, lists routes that pass through it with no alt-route bypass.
MATCH ()-[r:ROAD_SEGMENT {altRoute: false}]->(b:Bridge)
WITH b, collect(DISTINCT r.routeId) AS all_routes
MATCH ()-[r2:ROAD_SEGMENT {altRoute: true}]->()
WITH b, all_routes, collect(DISTINCT r2.routeId) AS protected
WITH b, [x IN all_routes WHERE NOT x IN protected] AS unprotected
WHERE size(unprotected) > 0
RETURN b.id, b.tier,
       size(unprotected)  AS unprotected_count,
       unprotected        AS unprotected_routes
ORDER BY unprotected_count DESC;

// ── F. Orphan check — nodes with no edges ─────────────────────────────────
// Expected: 0 rows
MATCH (n) WHERE NOT (n)--()
RETURN labels(n)[0] AS label, n.id, n.name;

// ── F2. Orphan neighborhoods — NBH that can't reach SJH ───────────────────
// Expected: 0
MATCH (n:Neighborhood)
WHERE NOT EXISTS {
  MATCH (n)-[:ROAD_SEGMENT*]->(s:School {id: 'SJH'}) }
RETURN count(n) AS orphaned_neighborhoods;

// ── G. Bypass path coverage by bridge ─────────────────────────────────────
// Which bridges have any alt-route bypass coverage at all?
MATCH ()-[r:ROAD_SEGMENT {altRoute: false}]->(b:Bridge)
WITH b, collect(DISTINCT r.routeId) AS primary_routes
MATCH ()-[r2:ROAD_SEGMENT {altRoute: true}]->()
WITH b, primary_routes, collect(DISTINCT r2.routeId) AS bypass_routes
WITH b,
     size(primary_routes) AS total,
     size([x IN primary_routes WHERE x IN bypass_routes]) AS covered
RETURN b.id, b.tier, total,
       covered,
       (total - covered) AS unprotected,
       CASE WHEN covered > 0 THEN 'Has bypass' ELSE 'NO BYPASS' END AS status
ORDER BY unprotected DESC;

// ── H. Patch 1 full detour path verification ──────────────────────────────
// Confirms all 7 hops of the Cooper/I-71 bypass exist for RD_COOPER.
MATCH (a)-[r:ROAD_SEGMENT {altRoute: true, routeId: 'RD_COOPER'}]->(b)
RETURN a.id AS from, b.id AS to, r.road AS road, r.seq AS seq
ORDER BY seq;

// ── I. Patch 2 full detour path verification ──────────────────────────────
// Confirms the Kenwood ODOT detour hops exist for RD_KENWOOD.
MATCH (a)-[r:ROAD_SEGMENT {altRoute: true, routeId: 'RD_KENWOOD'}]->(b)
RETURN a.id AS from, b.id AS to, r.road AS road, r.seq AS seq
ORDER BY seq;

// ── J. Node count by label ────────────────────────────────────────────────
// Expected: Neighborhood=134, Intersection=74, Bridge=12, School=1
MATCH (n)
RETURN labels(n)[0] AS label, count(n) AS count
ORDER BY count DESC;

// ── K. Route count ────────────────────────────────────────────────────────
// Expected: 74
MATCH ()-[r:ROAD_SEGMENT {altRoute: false}]->()
RETURN count(DISTINCT r.routeId) AS primary_routes;

// ── L. Edge split ─────────────────────────────────────────────────────────
// Expected: false=545, true=202
MATCH ()-[r:ROAD_SEGMENT]->()
RETURN r.altRoute AS bypass, count(r) AS edges
ORDER BY bypass;

// ── M. Duplicate constraint check ─────────────────────────────────────────
// Expected: 0 rows (constraints prevent duplicates)
MATCH (n)
WITH n.id AS id, count(n) AS cnt
WHERE cnt > 1
RETURN id, cnt
ORDER BY cnt DESC;

// ── N. Bridge properties spot-check ───────────────────────────────────────
// Verify all 12 bridges have tier and note fields populated.
MATCH (b:Bridge)
RETURN b.id, b.tier, b.road, b.crosses, b.note
ORDER BY b.tier, b.id;
