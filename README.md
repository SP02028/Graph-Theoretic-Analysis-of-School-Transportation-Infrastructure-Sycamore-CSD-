# Graph-Theoretic Analysis of School Transportation Infrastructure — Sycamore CSD

> Full article published on Medium: <https://medium.com/p/c5fa24c09894>

---

## Overview

This project applies graph theory and Neo4j's Graph Data Science (GDS) algorithms to model and analyze the school bus transportation network serving Sycamore Community School District (CSD). The goal is to identify which intersections and bridges are structural bottlenecks — nodes whose failure or closure would disrupt the largest number of student bus routes.

The network is modeled as a directed weighted graph where:

- **Nodes** represent neighborhoods (origins), road intersections, bridges, and the destination school (SJH).
- **Edges** (`ROAD_SEGMENT` relationships) represent road segments labeled with a `routeId`, a sequence number, and an `altRoute` flag that distinguishes primary routes from designated bypass detours.

---

## Graph Statistics

| Metric | Value |
|---|---|
| Total nodes | 221 |
| Neighborhoods | 134 |
| Intersections | 74 |
| Bridges | 12 |
| School | 1 |
| Primary edges (`altRoute: false`) | 545 |
| Alternate/bypass edges (`altRoute: true`) | 202 |
| Total bus routes | 74 |

---

## Methodology

Three centrality algorithms from the Neo4j GDS library were run on the network and then combined into a single composite vulnerability score.

### Betweenness Centrality (BC)

Measures how often a node appears on the shortest path between every pair of nodes in the graph. A high BC score means the node is a routing chokepoint — many routes must pass through it.

**Graph projection used:** directed, primary edges only (`altRoute: false`).

**Top result:** `BRG_MONTGOMERY_CREEK` (normalized BC = 1.000)

### PageRank (PR)

Measures downstream flow convergence. A node with high PR receives traffic from other high-PR nodes, making it a natural confluence point for many routes.

**Parameters:** damping factor = 0.85, max iterations = 200.

**Top result:** `INT_COOPER_DELRAY` (normalized PR = 1.000), `SJH` (PR = 0.876)

### Eigenvector Centrality (EV)

Measures structural embeddedness — nodes that are connected to many other well-connected nodes score highly. This is computed on an **undirected** projection of the graph because a directed graph collapses EV scores to the sink node only.

**Top result:** `INT_COOPER_DELRAY` (normalized EV = 1.000), `INT_KENWOOD_COOPER` (EV = 0.482)

### Composite Score

The three normalized scores are combined using a weighted formula:

```
Composite = 0.40 × BC + 0.35 × PR + 0.25 × EV
```

BC receives the highest weight because the study's primary concern is network disruption from a single point of failure; betweenness most directly captures that risk.

---

## Key Findings

### Top 5 Nodes by Composite Score (March 2026, GDS v3.1)

| Node | Type | BC | PR | EV | Composite |
|---|---|---|---|---|---|
| `INT_COOPER_DELRAY` | Intersection | 0.648 | 1.000 | 1.000 | **0.859** |
| `BRG_MONTGOMERY_CREEK` | Bridge | 1.000 | 0.469 | 0.033 | **0.572** |
| `BRG_COOPER_I71` | Bridge | 0.615 | 0.491 | 0.307 | **0.494** |
| `INT_COOPER_MONTGOMERY` | Intersection | 0.759 | 0.408 | 0.139 | **0.481** |
| `BRG_KENWOOD_CREEK` | Bridge | 0.569 | 0.462 | 0.315 | **0.468** |

### Bridge Vulnerability Summary

All 12 bridges were evaluated for route exposure and bypass coverage.

| Bridge | Tier | Primary Routes | Protected | Unprotected |
|---|---|---|---|---|
| `BRG_COOPER_I71` | T1-CRITICAL | 36 | 25 | 11 |
| `BRG_MONTGOMERY_CREEK` | T1-CRITICAL | 30 | — | — |
| `BRG_KENWOOD_CREEK` | — | 23 | — | — |

**Cooper/I-71 Bridge** is the highest-exposure bridge with 36 primary routes passing through it. 25 of those routes have a designated bypass (Patch 1 — the Montgomery/Pfeiffer corridor detour). The remaining 11 routes were identified in the v3 ArcGIS map audit as physically capable of using the bypass but not yet wired into the alternate-route layer.

**Kenwood Creek Bridge** has the most structurally embedded approach network: 22 distinct intersection nodes feed directly into it, giving it the highest eigenvector centrality of any bridge.

### Montgomery Corridor Dominance

Four of the top five betweenness centrality nodes are located on the Montgomery Road corridor:

- `BRG_MONTGOMERY_CREEK`
- `INT_SNIDER_KEMPER`
- `INT_COOPER_MONTGOMERY`
- `INT_KEMPER_MONTGOMERY`

This reflects the fact that Montgomery Road is the primary spine connecting the eastern neighborhoods to SJH.

---

## Bypass Patches

Two alternate-route patches were modeled to capture ODOT-approved detours:

- **Patch 1 — Cooper/I-71 bypass:** 25 routes rerouted via `INT_COOPER_MONTGOMERY` → `INT_MONTGOMERY_PFEIFFER`, bypassing the Cooper/I-71 overpass.
- **Patch 2 — Kenwood ODOT detour:** 13 routes rerouted via `INT_REED_HARTMAN_GM` → `INT_REED_HARTMAN_MALSBARY`, bypassing Kenwood Creek Bridge using an official ODOT detour corridor.

---

## Repository Contents

| File | Description |
|---|---|
| `13_verify_charts.cypher` | Structural verification queries — confirms graph topology matches the claims and charts in the article. Read-only. |
| `14_gds_centrality.cypher` | Neo4j GDS centrality algorithm queries (BC, PR, EV) and the composite ranking query. Requires GDS plugin. |
| `15_edge_cleanup.cypher` | Edge repair queries used during import debugging. Documents the history of a miscounted-edge bug and its targeted fix. |
| `16_analysis_adhoc.cypher` | Ad-hoc read-only analysis queries: health checks, bridge exposure rankings, route traversals, orphan checks, bypass coverage. |
| `index.html` | Interactive D3.js visualization of the three centrality scores across the network (BC, PR, EV panels). |
| `sjh_network_viz.html` | Full network visualization of the SJH transit graph. |

---

## How to Reproduce

### Prerequisites

- [Neo4j Desktop](https://neo4j.com/download/) with the **Graph Data Science** plugin installed (GDS ≥ 2.x)
- A populated SJH network graph (load files `09` → `10` → `11` from the original data import scripts)

### Verify graph health

Run the health-check query from `16_analysis_adhoc.cypher` (section A). A healthy graph returns:

```
nodes=221  primary=545  alt=202  health=PASS
```

### Run centrality analysis

Open `14_gds_centrality.cypher` in Neo4j Browser and execute the steps in order:

1. Check GDS is available
2. Drop any stale projections
3. Project `sjh-primary` (directed, primary edges) for BC and PR
4. Project `sjh-undirected` (all edges, undirected) for EV
5. Run BC, PR, and EV streams
6. Run the composite query (step 8) for the final ranking
7. Drop projections when finished

### Verify charts

Use `13_verify_charts.cypher` to confirm that the graph topology matches the specific numbers cited in the article (node counts, route counts, bridge exposure, bypass coverage).
