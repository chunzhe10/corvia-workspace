#!/usr/bin/env python3
"""
Corvia RAG Ask Mode Evaluation — Faithfulness & Answer Relevance

Evaluates the full RAG pipeline (retrieval + augmentation + generation)
using Jason Liu's 6 RAG eval framework. Focuses on:
- C|Q (Context Relevance): Is retrieved context relevant to the question?
- A|C (Faithfulness): Is the answer grounded in retrieved context?
- A|Q (Answer Relevance): Does the answer address the question?

Uses corvia's own knowledge base as ground truth (dogfooding).

Requires: corvia server with chat model loaded (corvia serve with inference).

Usage:
    python3 benchmarks/rag-retrieval/eval-ask-mode.py [--server URL]
"""

import json
import time
import sys
import argparse
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.error import URLError

RESULTS_DIR = Path(__file__).parent / "results"

# Subset of queries suitable for ask-mode evaluation (need clear expected answers)
ASK_QUERIES = [
    {
        "id": "ask-litestore",
        "query": "What is LiteStore and how does it store data?",
        "expected_keywords": ["json", "redb", "hnsw", "git", "zero-docker"],
        "expected_answer_contains": ["json", "redb"],
        "category": "architecture",
    },
    {
        "id": "ask-agpl",
        "query": "Why does corvia use AGPL-3.0 licensing?",
        "expected_keywords": ["saas", "protection", "dual", "commercial"],
        "expected_answer_contains": ["saas", "protection"],
        "category": "decision",
    },
    {
        "id": "ask-graph-expand",
        "query": "How does graph-expanded retrieval work in corvia?",
        "expected_keywords": ["petgraph", "bfs", "edges", "vector", "hnsw"],
        "expected_answer_contains": ["graph", "vector"],
        "category": "feature",
    },
    {
        "id": "ask-merge",
        "query": "How does corvia handle merge conflicts between agents?",
        "expected_keywords": ["llm", "semantic", "similarity", "conflict"],
        "expected_answer_contains": ["llm", "conflict"],
        "category": "feature",
    },
    {
        "id": "ask-embedding-models",
        "query": "What embedding models does corvia support?",
        "expected_keywords": ["nomic", "minilm", "bge", "snowflake", "gte"],
        "expected_answer_contains": ["nomic", "768"],
        "category": "config",
    },
]


def rag_ask(server: str, query: str) -> dict:
    """Call corvia's /v1/ask endpoint (full RAG with generation)."""
    payload = json.dumps({
        "query": query,
        "scope_id": "corvia",
        "limit": 10,
    }).encode()

    req = Request(f"{server}/v1/ask", data=payload,
                  headers={"Content-Type": "application/json"})
    start = time.monotonic()
    try:
        with urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read())
            latency_ms = (time.monotonic() - start) * 1000
    except (URLError, TimeoutError) as e:
        return {"error": str(e), "latency_ms": 0}

    return {
        "answer": data.get("answer"),
        "sources": data.get("sources", []),
        "latency_ms": latency_ms,
        "error": None,
    }


def eval_context_relevance(query: str, sources: list, expected_keywords: list) -> float:
    """C|Q: Is retrieved context relevant to the question?"""
    if not sources:
        return 0.0
    combined = " ".join(s.get("content", "") for s in sources).lower()
    found = sum(1 for kw in expected_keywords if kw.lower() in combined)
    return found / max(len(expected_keywords), 1)


def eval_faithfulness(answer: str, sources: list) -> float:
    """A|C: Is the answer grounded in retrieved context?
    Simple heuristic: what fraction of answer sentences have supporting content."""
    if not answer or not sources:
        return 0.0
    combined_context = " ".join(s.get("content", "") for s in sources).lower()
    # Split answer into sentences (rough)
    sentences = [s.strip() for s in answer.replace(".", ".\n").split("\n") if len(s.strip()) > 10]
    if not sentences:
        return 1.0  # Empty answer is trivially faithful
    grounded = 0
    for sent in sentences:
        # Check if key words from the sentence appear in context
        words = [w for w in sent.lower().split() if len(w) > 4]
        if not words:
            grounded += 1
            continue
        overlap = sum(1 for w in words if w in combined_context)
        if overlap / len(words) >= 0.3:
            grounded += 1
    return grounded / len(sentences)


def eval_answer_relevance(answer: str, query: str, expected_contains: list) -> float:
    """A|Q: Does the answer address the question?"""
    if not answer:
        return 0.0
    answer_lower = answer.lower()
    found = sum(1 for kw in expected_contains if kw.lower() in answer_lower)
    return found / max(len(expected_contains), 1)


def main():
    parser = argparse.ArgumentParser(description="Corvia Ask Mode Evaluation")
    parser.add_argument("--server", default="http://localhost:8020")
    args = parser.parse_args()

    print("Corvia RAG Ask Mode Evaluation (Jason Liu's 6 Evals)")
    print(f"Server: {args.server}")
    print(f"Queries: {len(ASK_QUERIES)}")
    print("-" * 70)

    results = []
    for q in ASK_QUERIES:
        response = rag_ask(args.server, q["query"])
        if response.get("error"):
            print(f"  ERROR {q['id']}: {response['error']}")
            results.append({"id": q["id"], "error": response["error"]})
            continue

        sources = response["sources"]
        answer = response.get("answer") or ""

        # Context-only mode returns sources but no answer
        # Evaluate what we can
        cq = eval_context_relevance(q["query"], sources, q["expected_keywords"])

        if answer:
            ac = eval_faithfulness(answer, sources)
            aq = eval_answer_relevance(answer, q["query"], q["expected_answer_contains"])
        else:
            ac = None
            aq = None

        result = {
            "id": q["id"],
            "category": q["category"],
            "context_relevance": round(cq, 3),
            "faithfulness": round(ac, 3) if ac is not None else None,
            "answer_relevance": round(aq, 3) if aq is not None else None,
            "source_count": len(sources),
            "has_answer": bool(answer),
            "latency_ms": round(response["latency_ms"], 1),
        }
        results.append(result)

        status = "FULL" if answer else "CTX"
        print(f"  [{status}] {q['id']:<25} C|Q={cq:.2f} "
              f"A|C={'N/A' if ac is None else f'{ac:.2f}'} "
              f"A|Q={'N/A' if aq is None else f'{aq:.2f}'} "
              f"src={len(sources)} {response['latency_ms']:.0f}ms")

    # Summary
    valid = [r for r in results if "error" not in r]
    print("-" * 70)
    if valid:
        avg_cq = sum(r["context_relevance"] for r in valid) / len(valid)
        full = [r for r in valid if r["faithfulness"] is not None]
        avg_ac = sum(r["faithfulness"] for r in full) / len(full) if full else 0
        avg_aq = sum(r["answer_relevance"] for r in full) / len(full) if full else 0

        print(f"Context Relevance (C|Q): {avg_cq:.3f}")
        print(f"Faithfulness (A|C):      {avg_ac:.3f}" + (" (context-only mode)" if not full else ""))
        print(f"Answer Relevance (A|Q):  {avg_aq:.3f}" + (" (context-only mode)" if not full else ""))
        print(f"Queries with generation: {len(full)}/{len(valid)}")

    # Save results
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    output = {
        "timestamp": timestamp,
        "server": args.server,
        "mode": "ask",
        "evals": ["context_relevance", "faithfulness", "answer_relevance"],
        "summary": {
            "avg_context_relevance": round(avg_cq, 3) if valid else 0,
            "avg_faithfulness": round(avg_ac, 3) if valid else 0,
            "avg_answer_relevance": round(avg_aq, 3) if valid else 0,
            "queries_with_generation": len(full) if valid else 0,
        },
        "details": results,
    }
    path = RESULTS_DIR / f"eval-ask-{timestamp}.json"
    with open(path, "w") as f:
        json.dump(output, f, indent=2)
    print(f"\nResults saved to: {path}")


if __name__ == "__main__":
    main()
