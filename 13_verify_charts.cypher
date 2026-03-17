// ════════════════════════════════════════════════════════════════════════
// 13_verify_charts.cypher
// Structural verification queries — confirm graph topology matches
// the claims and charts in the paper.
// READ ONLY — no writes. Safe to run at any time.
//
// All queries operate on primary edges (altRoute: false) only,
// which is the dataset the centrality algorithms were computed on.
// ════════════════════════════════════════════════════════════════════════

// ── Chart 1 proxy: Betweenness Centrality ────────────────────────────────
// BC measures nodes on the most shortest paths.
// Structural proxy: which nodes do the most routes pass through?
// Expected top 3: INT_COOPER_DELRAY=73, BRG_COOPER_I71=36,
//                 INT_COOPER_MONTGOMERY=30 / BRG_MONTGOMERY_CREEK=30
MATCH ()-[r:ROAD_SEGMENT {altRoute: false}]->(n)
WHERE n:Bridge OR n:Intersection
RETURN labels(n)[0]               AS type,
       n.id                        AS node,
       count(DISTINCT r.routeId)   AS routes_through
ORDER BY routes_through DESC
LIMIT 10;

// ── BC: confirm Montgomery corridor dominance ─────────────────────────────
// The paper claims 4 of the top 5 BC nodes are on Montgomery Rd.
MATCH ()-[r:ROAD_SEGMENT {altRoute: false}]->(n)
WHERE n.id IN [
  'BRG_MONTGOMERY_CREEK',
  'INT_SNIDER_KEMPER',
  'INT_COOPER_MONTGOMERY',
  'INT_KEMPER_MONTGOMERY',
  'BRG_FIELDS_ERTEL_CREEK'
]
RETURN n.id                        AS node,
       count(DISTINCT r.routeId)   AS routes_through
ORDER BY routes_through DESC;

// ── Chart 2 proxy: PageRank ───────────────────────────────────────────────
// PR measures downstream flow convergence.
// Expected: SJH=74, INT_COOPER_DELRAY=73, BRG_COOPER_I71=36
MATCH (up)-[r:ROAD_SEGMENT {altRoute: false}]->(n)
WHERE n:Bridge OR n:Intersection OR n:School
RETURN labels(n)[0]               AS type,
       n.id                        AS node,
       count(DISTINCT up.id)       AS direct_feeders,
       count(DISTINCT r.routeId)   AS routes_feeding
ORDER BY routes_feeding DESC
LIMIT 10;

// ── PR: confirm Cooper/I-71 is highest-PR bridge ──────────────────────────
// GDS verified: BRG_COOPER_I71=0.491, BRG_MONTGOMERY_CREEK=0.469,
//               BRG_KENWOOD_CREEK=0.462
MATCH (up)-[r:ROAD_SEGMENT {altRoute: false}]->(b:Bridge)
RETURN b.id                        AS bridge,
       b.tier,
       count(DISTINCT up.id)        AS direct_feeders,
       count(DISTINCT r.routeId)    AS routes_feeding
ORDER BY routes_feeding DESC;

// ── Chart 3: Eigenvector — confirm Kenwood star topology ──────────────────
// EV measures structural embeddedness.
// BRG_KENWOOD_CREEK has 22 distinct approach intersections — most of any bridge.
MATCH (approach)-[r:ROAD_SEGMENT {altRoute: false}]->(b:Bridge)
RETURN b.id                          AS bridge,
       b.tier,
       count(DISTINCT approach.id)   AS approach_nodes,
       count(DISTINCT r.routeId)     AS routes
ORDER BY approach_nodes DESC;

// ── EV: list all 22 Kenwood approach nodes ────────────────────────────────
MATCH (approach)-[r:ROAD_SEGMENT {altRoute: false}]->
      (b:Bridge {id: 'BRG_KENWOOD_CREEK'})
RETURN approach.id                AS approach_node,
       labels(approach)[0]        AS type,
       count(DISTINCT r.routeId)  AS routes
ORDER BY routes DESC;

// ── Chart 4: Cooper/I-71 doughnut — 25 protected vs 11 unprotected ───────
// Expected: protected=25, unprotected=11
MATCH ()-[r:ROAD_SEGMENT {altRoute: false}]->(b:Bridge {id: 'BRG_COOPER_I71'})
WITH collect(DISTINCT r.routeId) AS cooper_routes
MATCH ()-[r2:ROAD_SEGMENT {altRoute: true}]->()
WITH cooper_routes, collect(DISTINCT r2.routeId) AS bypass_routes
UNWIND cooper_routes AS route
RETURN
  count(CASE WHEN route IN bypass_routes     THEN 1 END) AS protected,
  count(CASE WHEN NOT route IN bypass_routes THEN 1 END) AS unprotected;

// ── Bridge vulnerability table — all 12 bridges ───────────────────────────
MATCH ()-[r:ROAD_SEGMENT {altRoute: false}]->(b:Bridge)
WITH b, collect(DISTINCT r.routeId) AS primary_routes
MATCH ()-[r2:ROAD_SEGMENT {altRoute: true}]->()
WITH b, primary_routes, collect(DISTINCT r2.routeId) AS bypass_routes
RETURN
  b.id                                                              AS bridge,
  b.tier,
  size(primary_routes)                                              AS primary_route_count,
  size([x IN primary_routes WHERE NOT x IN bypass_routes])         AS unprotected_routes,
  size([x IN primary_routes WHERE x IN bypass_routes])             AS protected_routes
ORDER BY primary_route_count DESC;

// ── Stats row (Fig 1) — expected: 134/74/12/1/221/74 ─────────────────────
MATCH (n)
WITH
  count(CASE WHEN n:Neighborhood THEN 1 END) AS neighborhoods,
  count(CASE WHEN n:Intersection THEN 1 END) AS intersections,
  count(CASE WHEN n:Bridge       THEN 1 END) AS bridges,
  count(CASE WHEN n:School       THEN 1 END) AS school
MATCH ()-[r:ROAD_SEGMENT {altRoute: false}]->()
RETURN neighborhoods, intersections, bridges, school,
       (neighborhoods + intersections + bridges + school) AS total_nodes,
       count(DISTINCT r.routeId) AS routes;

// ── Patch 1: 25 routes via Cooper/I-71 bypass ─────────────────────────────
MATCH (a:Intersection {id: 'INT_COOPER_MONTGOMERY'})
     -[r:ROAD_SEGMENT {altRoute: true}]->
     (b:Intersection {id: 'INT_MONTGOMERY_PFEIFFER'})
RETURN r.routeId AS route
ORDER BY route;

// ── Patch 2: 13 routes via Kenwood ODOT detour ────────────────────────────
MATCH (a:Intersection {id: 'INT_REED_HARTMAN_GM'})
     -[r:ROAD_SEGMENT {altRoute: true}]->
     (b:Intersection {id: 'INT_REED_HARTMAN_MALSBARY'})
RETURN r.routeId AS route
ORDER BY route;

// ── 11 unprotected Cooper routes ──────────────────────────────────────────
// All 11 were added in the v3 ArcGIS map audit.
// They can physically use Patch 1 but are not yet wired in the alt-route layer.
MATCH ()-[r:ROAD_SEGMENT {altRoute: false}]->(b:Bridge {id: 'BRG_COOPER_I71'})
WITH collect(DISTINCT r.routeId) AS all_routes
MATCH ()-[r2:ROAD_SEGMENT {altRoute: true}]->()
WITH all_routes, collect(DISTINCT r2.routeId) AS protected
UNWIND all_routes AS route
WITH route, protected WHERE NOT route IN protected
RETURN route AS unprotected_route
ORDER BY route;
