"""
Mock LLM — expose une API compatible OpenAI /v1/chat/completions
Utilisé dans Docker Compose pour tester sans clé OpenAI réelle.
Affiche dans les logs ce qu'il reçoit et ce qu'il renvoie.
"""
import json
import time
import uuid
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

app = FastAPI(title="Mock LLM")


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    body = await request.json()
    messages = body.get("messages", [])
    model = body.get("model", "gpt-4o-mini")

    # Affiche ce qui a été reçu (utile pour vérifier le masquage PII)
    print("\n=== Mock LLM — requête reçue ===")
    for msg in messages:
        role = msg.get("role", "?")
        content = msg.get("content", "")
        print(f"  [{role}] {content}")

    # Construit une réponse factice mais réaliste
    last_user = next(
        (m["content"] for m in reversed(messages) if m.get("role") == "user"),
        "Bonjour",
    )
    reply = f"[Mock LLM] J'ai bien reçu votre message : « {last_user[:80]} »"

    response = {
        "id": f"chatcmpl-{uuid.uuid4().hex[:8]}",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": reply},
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": sum(len(m.get("content", "")) // 4 for m in messages),
            "completion_tokens": len(reply) // 4,
            "total_tokens": (
                sum(len(m.get("content", "")) // 4 for m in messages)
                + len(reply) // 4
            ),
        },
    }

    print(f"=== Mock LLM — réponse envoyée ===\n  {reply}\n")
    return JSONResponse(response)
