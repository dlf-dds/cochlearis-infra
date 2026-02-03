## AGENTEXPERT.md
### To implement Later

The concept of **GitHub Custom Agents** (via `.agent.md` files) is effectively a "Serverless AI Colleague." Instead of managing a separate bot server, you are providing a structured **operating manual** that GitHub Copilot uses to transform itself into a specialist for your repository.

When any of your 100 engineers use Copilot Chat, they can invoke this "persona," and it will answer with the specific context, rules, and "hard-won" lessons you've embedded in the file.

---

### How to Implement It

#### 1. The Directory Structure

GitHub looks for these agents in a specific hidden folder.

* **Path:** `.github/agents/`
* **File naming:** `[agent-name].agent.md` (The `.agent.md` extension is critical).

#### 2. The Anatomy of an `.agent.md` File

The file is split into two sections: **Metadata (YAML)** and **Instructions (Markdown)**.

```markdown
---
name: "Fabric Architect"
description: "Expert in Zenoh, OpenZiti, and European Theater Data Fabric"
tools: ["*"] 
---

# Role & Context
You are the senior advisor for Project Almond Bread. You exist to prevent 
engineers from falling into "Fix Loop Hell" by enforcing proven infrastructure patterns.

# Project Constraints
- We use AWS ECS Fargate with an Internal ALB for hairpin NAT.
- Do NOT use Zitadel OIDC; we have pivoted to Azure AD.
- All ADRs are stored in /docs/adrs.

# Preferred Response Style
Answer in a direct, earnest, Hemingway-style prose. No corporate jargon.

```

#### 3. How the Team Uses It

Once you push this file to your `main` branch:

1. **In VS Code:** Engineers open Copilot Chat and type `@` followed by your agent's name (e.g., `@fabric-architect`).
2. **On GitHub.com:** The agent appears in the "Agents" tab of the Copilot sidebar.
3. **In the Terminal:** If they use the Copilot CLI, they can run `copilot --agent fabric-architect "How do I route Zenoh traffic?"`.

---

### Why this beats "Clawbot" for your situation

* **No Sidecars or Networking:** You don't have to deal with EFS permissions, ALB health checks, or Redis timeouts. If GitHub is up, your agent is up.
* **Implicit Context:** The agent has a "Grounding" advantage. It automatically "reads" your entire repository (Terraform, Readmes, Code) to ensure its advice doesn't contradict your actual infrastructure.
* **Low Maintenance:** If you find a new "Gotcha" (like the Zulip Python tuple requirement), you just add one line to the Markdown file and push. Every engineer’s AI assistant is instantly updated.

### The "Pro" Move: MCP Tools

If you eventually want the agent to actually *do* things (like query your AWS environment or check Mattermost), you can link it to **MCP (Model Context Protocol)** servers. This allows the agent to use external tools you define without the agent itself needing to be "hosted" as a service.

**Would you like me to write a "Template" for a different agent—perhaps a "DevOps/SRE Agent" specifically for managing your ECR/ECS deployments?**