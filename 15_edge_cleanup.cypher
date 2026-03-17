// ════════════════════════════════════════════════════════════════════════
// 15_edge_cleanup.cypher
// Edge repair queries used during the import debugging session.
// DOCUMENTED HERE FOR REFERENCE — do not re-run unless you have the
// specific problem these were written to fix.
//
// PROBLEM HISTORY:
//   The original sjh_network_v3.cypher wrote 26 Patch 2 (ODOT detour)
//   edges with altRoute:false instead of altRoute:true. This caused:
//     primary=571 (should be 545) — 26 edges miscounted as primary
//     alt=176     (should be 202) — 26 Patch 2 edges missing from alt
//
//   Resolution: delete all edges, reload files 09 → 10 → 11 cleanly.
//   Two residual false-duplicate edges remained after reload and were
//   deleted by the targeted queries below.
// ════════════════════════════════════════════════════════════════════════

// ── DIAGNOSTIC: check current edge split ─────────────────────────────────
// Run this first to see what state your graph is in.
MATCH ()-[r:ROAD_SEGMENT]->()
RETURN r.altRoute AS bypass, count(r) AS edges
ORDER BY bypass;
// Healthy graph: false=545, true=202

// ── NUCLEAR OPTION: wipe all edges and reload ─────────────────────────────
// Use this if the edge split is wrong and targeted fixes aren't working.
// After running, reload files 09, 10, 11 in order.
// MATCH ()-[r:ROAD_SEGMENT]->() DELETE r;

// ── TARGETED FIX A: delete false-duplicate Malsbary hops ─────────────────
// These two queries remove the 26 residual altRoute:false duplicates
// on the Patch 2 Kenwood detour path.
// Only needed if primary > 545 and alt < 202.

// Step 1 — delete GM → Malsbary false edges (expected: 13 deleted)
MATCH (a:Intersection {id: 'INT_REED_HARTMAN_GM'})
     -[r:ROAD_SEGMENT {altRoute: false}]->
     (b:Intersection {id: 'INT_REED_HARTMAN_MALSBARY'})
DELETE r;

// Step 2 — delete Malsbary → Cooper false edges (expected: 13 deleted)
MATCH (a:Intersection {id: 'INT_REED_HARTMAN_MALSBARY'})
     -[r:ROAD_SEGMENT {altRoute: false}]->
     (b:Intersection {id: 'INT_COOPER_REED_HARTMAN'})
DELETE r;

// ── VERIFY after fix ──────────────────────────────────────────────────────
// Expected: false=545, true=202, total=747, health=PASS
MATCH (n) WITH count(n) AS nodes
MATCH ()-[r:ROAD_SEGMENT]->() WHERE r.altRoute = false
WITH nodes, count(r) AS primary
MATCH ()-[r2:ROAD_SEGMENT]->() WHERE r2.altRoute = true
WITH nodes, primary, count(r2) AS alt
RETURN nodes, primary, alt, (primary + alt) AS total_edges,
       CASE WHEN nodes = 221 AND primary = 545 AND alt = 202
            THEN 'PASS' ELSE 'FAIL' END AS health;
