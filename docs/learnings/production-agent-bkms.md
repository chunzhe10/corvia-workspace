# Production Agent BKMs

Best Known Methods for building production-grade AI agents, adapted from
[agents-towards-production](https://github.com/NirDiamant/agents-towards-production).

## Architecture

- **Graph-based orchestration**: Use directed graph architectures with explicit state
  transitions for multi-step workflows. Avoid linear chains for anything non-trivial.
- **Layered separation of concerns**: Keep orchestration, memory, tools, security, and
  evaluation as distinct layers. Do not mix tool-calling logic with reasoning logic.
- **Protocol-first integration**: Adopt MCP for tool integration and A2A for multi-agent
  communication. Protocol-based design makes agents composable and replaceable.

## Memory Systems

- **Dual-memory architecture**: Short-term (session/conversation context) + long-term
  (persistent knowledge with semantic search — this is what corvia provides).
- **Self-improving memory**: Design memory that evolves through interaction — automatic
  insight extraction, conflict resolution, and knowledge consolidation across sessions.

## Security (Defense-in-Depth)

- **Three-layer guardrails**: Input validation (prompt injection prevention), behavioral
  constraints (during execution), and output filtering (before delivery to user).
- **Tool access control**: Restrict which tools an agent can invoke based on user context
  and permissions. Never give agents unrestricted access to external tools.
- **User isolation**: Prevent cross-user data leakage in multi-user deployments.

## Observability

- **Trace every decision point**: Capture the full reasoning chain — which tools were
  called, what the LLM decided, timing data for each step.
- **Instrument from day one**: Do not bolt on observability later. Traces are essential
  for debugging, performance analysis, and evaluation.
- **Monitor cost, latency, accuracy** continuously, not just during development.

## Evaluation & Testing

- **Domain-specific test suites**: Build evaluation sets tailored to your domain.
  Generic benchmarks are insufficient.
- **Multi-dimensional metrics**: Evaluate beyond accuracy — include cost per interaction,
  latency, safety compliance, and tool-use correctness.
- **Iterative improvement cycles**: Evaluation should produce actionable insights that
  feed back into agent refinement.

## Deployment Strategy

- **Containerize everything**: Docker for portability and environment consistency.
- **Start stateless, migrate to persistent**: Prototype without memory, then layer in
  persistence once the workflow is stable.
- **Production readiness progression**: Prototype → Functional (add memory, auth, tracing)
  → Production (guardrails, evaluation, observability) → Scaled (multi-agent, GPU, fine-tuning).
