"""
Phase 1c — Agentic RAG. The merge of the two halves of Phase 1.

agent_loop.py gave us a model that can call tools in a loop.
rag.py gave us retrieval over a knowledge base in Postgres.

This file joins them: retrieval becomes ONE OF THE TOOLS the agent can
call. The consequence is the whole point — the model now DECIDES, per
question, whether it needs to search the knowledge base at all:

  - "what is 2+2?"          -> answers directly, never searches
  - "how do I fix Kyverno?" -> chooses to call search_knowledge_base,
                               gets chunks, then answers from them
  - "fix Kyverno AND Falco" -> may call search twice, once per topic

Retrieval is no longer a fixed step you always run (as in rag.py). It is
a capability the model reaches for when it judges it useful. That is
"agentic RAG".

Run: OPENAI_API_KEY=sk-... DATABASE_URL=postgres://... python agentic_rag.py
"""
import json
import os
import psycopg
from openai import OpenAI

# Reuse the real functions from the two Phase 1 scripts — no copy-paste.
# rag.py gives us the retrieval pipeline; we import its pieces directly.
from rag import init_db, ingest, retrieve, SAMPLE
from agent_loop import get_weather, add  # keep the old tools too, to show mixing

client = OpenAI()
MODEL = "gpt-4o-mini"


# ---------------------------------------------------------------------------
# The tools. get_weather and add come straight from agent_loop.py. The new
# one is search_knowledge_base — but note it needs a DB connection, which
# the model must NOT see or supply. We solve that with a closure (below in
# build_tools) that captures the connection, exposing a tool that takes
# only a `query` string. The model decides WHAT to search for; the
# connection is our plumbing, invisible to the model.
# ---------------------------------------------------------------------------
def build_tools(conn):
    def search_knowledge_base(query: str) -> dict:
        chunks = retrieve(conn, query, k=4)
        # Return structured data. The model reads this back as the tool
        # result and grounds its answer in these chunks.
        return {"query": query, "chunks": chunks, "num_results": len(chunks)}

    registry = {
        "get_weather": get_weather,
        "add": add,
        "search_knowledge_base": search_knowledge_base,
    }
    return registry


TOOL_SCHEMAS = [
    {
        "type": "function",
        "function": {
            "name": "search_knowledge_base",
            "description": (
                "Search the DevOps knowledge base for relevant notes. Use this "
                "whenever the question might be answered by internal documentation "
                "about Kubernetes, Kyverno, Cosign, Falco, spot node pools, or "
                "similar operational topics. Returns the most relevant text chunks."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "What to search for, as a natural-language query.",
                    }
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get the current temperature for a city.",
            "parameters": {
                "type": "object",
                "properties": {"city": {"type": "string", "description": "City name"}},
                "required": ["city"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "add",
            "description": "Add two numbers.",
            "parameters": {
                "type": "object",
                "properties": {"a": {"type": "number"}, "b": {"type": "number"}},
                "required": ["a", "b"],
            },
        },
    },
]


# ---------------------------------------------------------------------------
# The loop — IDENTICAL to agent_loop.py. This is the elegance of the merge:
# the loop machinery doesn't change at all. It dispatches whatever tools are
# in the registry. RAG is just one more tool it can pick up.
# ---------------------------------------------------------------------------
def run(user_prompt: str, tools: dict, max_turns: int = 10) -> str:
    # A light system prompt so the model knows the KB exists and prefers it
    # over guessing on operational questions.
    messages = [
        {
            "role": "system",
            "content": (
                "You are a DevOps assistant. When a question concerns internal "
                "operational topics, use search_knowledge_base and answer from the "
                "retrieved chunks. If the chunks don't contain the answer, say so. "
                "For general questions (math, weather) use the other tools or answer "
                "directly."
            ),
        },
        {"role": "user", "content": user_prompt},
    ]

    for _turn in range(max_turns):
        resp = client.chat.completions.create(
            model=MODEL, messages=messages, tools=TOOL_SCHEMAS
        )
        msg = resp.choices[0].message

        if not msg.tool_calls:
            return msg.content

        messages.append(msg)
        for call in msg.tool_calls:
            fn = tools[call.function.name]
            args = json.loads(call.function.arguments)
            result = fn(**args)
            # Print a compact trace so you can SEE the model's decisions.
            preview = result
            if call.function.name == "search_knowledge_base":
                preview = f"{result['num_results']} chunks for {result['query']!r}"
            print(f"  [tool] {call.function.name}({args}) -> {preview}")
            messages.append(
                {
                    "role": "tool",
                    "tool_call_id": call.id,
                    "content": json.dumps(result),
                }
            )

    return "(stopped: hit max_turns)"


if __name__ == "__main__":
    with psycopg.connect(os.environ["DATABASE_URL"], autocommit=False) as conn:
        init_db(conn)
        # Make the run idempotent for the demo.
        conn.execute("TRUNCATE chunks")
        conn.commit()
        ingest(conn, "lab-notes", SAMPLE)

        tools = build_tools(conn)

        # Three questions that should route THREE different ways:
        prompts = [
            "How do I make Kyverno work with Cosign v3?",  # -> should search KB
            "What is 47 plus 55?",                          # -> should use add, no search
            "Lund, temperature?",
            "How do I fix Kyverno with Cosign, and why does Falco crash?",  # -> may search twice
        ]
        for p in prompts:
            print(f"\nUSER: {p}")
            print(f"ASSISTANT: {run(p, tools)}")
