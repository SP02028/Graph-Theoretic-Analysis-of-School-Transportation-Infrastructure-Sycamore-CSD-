// ════════════════════════════════════════════════════════════════════════
// 14_gds_centrality.cypher
// Neo4j Graph Data Science (GDS) centrality algorithms.
// Requires GDS plugin installed in Neo4j Desktop (Plugins tab).
//
// RUN ORDER:
//   1. Check GDS is available
//   2. Drop any old projections
//   3. Create sjh-primary   (directed, altRoute:false only — for BC and PR)
//   4. Create sjh-undirected (undirected, all edges — for EV)
//   5. Run BC (betweenness)
//   6. Run PR (pageRank)
//   7. Run EV (eigenvector)
//   8. Run composite query (all three joined)
//   9. Drop projections when done
//
// VERIFIED SCORES (GDS v3.1 graph, March 2026):
//   BC: BRG_MONTGOMERY_CREEK=1.000  INT_SNIDER_KEMPER=0.759
//   PR: INT_COOPER_DELRAY=1.000     SJH=0.876
//   EV: INT_COOPER_DELRAY=1.000     INT_KENWOOD_COOPER=0.482
// ════════════════════════════════════════════════════════════════════════

// ── 1. Check GDS is available ─────────────────────────────────────────────
RETURN gds.version();

// ── 2. Drop old projections (safe — false = don't error if not found) ─────
CALL gds.graph.drop('sjh-primary',    false);
CALL gds.graph.drop('sjh-undirected', false);

// ── 3. Project primary-only directed graph (for BC and PR) ────────────────
// Uses only altRoute:false edges — matches the Python centrality input exactly.
// Expected: nodeCount=221, relationshipCount=545
CALL gds.graph.project.cypher(
  'sjh-primary',
  'MATCH (n)
   WHERE n:Neighborhood OR n:Intersection OR n:Bridge OR n:School
   RETURN id(n) AS id',
  'MATCH (a)-[r:ROAD_SEGMENT {altRoute: false}]->(b)
   RETURN id(a) AS source, id(b) AS target'
)
YIELD graphName, nodeCount, relationshipCount
RETURN graphName, nodeCount, relationshipCount;

// ── 4. Project undirected graph (for EV) ──────────────────────────────────
// Uses all edges with UNDIRECTED orientation.
// Expected: nodeCount=221, relationshipCount=1494
CALL gds.graph.project(
  'sjh-undirected',
  ['Neighborhood','Intersection','Bridge','School'],
  {ROAD_SEGMENT: {orientation: 'UNDIRECTED'}}
)
YIELD graphName, nodeCount, relationshipCount
RETURN graphName, nodeCount, relationshipCount;

// ── 5. Betweenness Centrality (normalized to max=1.0) ─────────────────────
// Expected top: BRG_MONTGOMERY_CREEK=1.000
CALL gds.betweenness.stream('sjh-primary')
YIELD nodeId, score
WITH gds.util.asNode(nodeId) AS n, score
WHERE score > 0 AND NOT n:Neighborhood
WITH labels(n)[0] AS type, n.id AS node, score
ORDER BY score DESC
WITH collect({type:type, node:node, score:score}) AS rows
WITH rows, rows[0].score AS maxScore
UNWIND rows AS r
RETURN r.type AS type, r.node AS node,
       round(r.score / maxScore, 4) AS bc
ORDER BY bc DESC
LIMIT 20;

// ── 6. PageRank (normalized to max=1.0) ───────────────────────────────────
// dampingFactor=0.85, maxIterations=200
// Expected top: INT_COOPER_DELRAY=1.000, SJH=0.876
CALL gds.pageRank.stream('sjh-primary', {
  dampingFactor: 0.85,
  maxIterations: 200
})
YIELD nodeId, score
WITH gds.util.asNode(nodeId) AS n, score
WHERE NOT n:Neighborhood
WITH labels(n)[0] AS type, n.id AS node, score
ORDER BY score DESC
WITH collect({type:type, node:node, score:score}) AS rows
WITH rows, rows[0].score AS maxScore
UNWIND rows AS r
RETURN r.type AS type, r.node AS node,
       round(r.score / maxScore, 4) AS pr
ORDER BY pr DESC
LIMIT 20;

// ── 7. Eigenvector Centrality (normalized to max=1.0) ─────────────────────
// Uses UNDIRECTED projection — directed graph collapses EV to sink node only.
// Expected top: INT_COOPER_DELRAY=1.000, SJH=0.558
CALL gds.eigenvector.stream('sjh-undirected', {
  maxIterations: 300
})
YIELD nodeId, score
WITH gds.util.asNode(nodeId) AS n, score
WHERE score > 0 AND NOT n:Neighborhood
WITH labels(n)[0] AS type, n.id AS node, score
ORDER BY score DESC
WITH collect({type:type, node:node, score:score}) AS rows
WITH rows, rows[0].score AS maxScore
UNWIND rows AS r
RETURN r.type AS type, r.node AS node,
       round(r.score / maxScore, 4) AS ev
ORDER BY ev DESC
LIMIT 20;

// ── 8. Composite score (all three algorithms joined) ──────────────────────
// Composite = 0.40*BC + 0.35*PR + 0.25*EV
// This is the definitive combined ranking query.
// Verified output (top 13, March 2026):
//   INT_COOPER_DELRAY      BC=0.648  PR=1.000  EV=1.000  comp=0.859
//   BRG_MONTGOMERY_CREEK   BC=1.000  PR=0.469  EV=0.033  comp=0.572
//   BRG_COOPER_I71         BC=0.615  PR=0.491  EV=0.307  comp=0.494
//   INT_COOPER_MONTGOMERY  BC=0.759  PR=0.408  EV=0.139  comp=0.481
//   BRG_KENWOOD_CREEK      BC=0.569  PR=0.462  EV=0.315  comp=0.468

CALL gds.betweenness.stream('sjh-primary')
YIELD nodeId, score AS bcRaw
WITH collect({id: nodeId, bc: bcRaw}) AS bcList,
     max(bcRaw) AS bcMax

CALL gds.pageRank.stream('sjh-primary', {
  dampingFactor: 0.85,
  maxIterations: 200
})
YIELD nodeId, score AS prRaw
WITH bcList, bcMax,
     collect({id: nodeId, pr: prRaw}) AS prList,
     max(prRaw) AS prMax

CALL gds.eigenvector.stream('sjh-undirected', {
  maxIterations: 300
})
YIELD nodeId, score AS evRaw
WITH bcList, bcMax, prList, prMax,
     collect({id: nodeId, ev: evRaw}) AS evList,
     max(evRaw) AS evMax

UNWIND bcList AS bcRow
WITH bcList, bcMax, prList, prMax, evList, evMax, bcRow,
     [x IN prList WHERE x.id = bcRow.id][0] AS prRow,
     [x IN evList WHERE x.id = bcRow.id][0] AS evRow
WITH gds.util.asNode(bcRow.id) AS n,
     round(bcRow.bc / bcMax, 4) AS bc,
     round(prRow.pr / prMax, 4) AS pr,
     round(evRow.ev / evMax, 4) AS ev
WHERE NOT n:Neighborhood
WITH labels(n)[0] AS type, n.id AS node, bc, pr, ev,
     round(0.40*bc + 0.35*pr + 0.25*ev, 4) AS composite
ORDER BY composite DESC
RETURN type, node, bc, pr, ev, composite
LIMIT 20;

// ── 9. Drop projections when done ─────────────────────────────────────────
CALL gds.graph.drop('sjh-primary');
CALL gds.graph.drop('sjh-undirected');
