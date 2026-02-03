# Documentation

This directory contains detailed documentation for the Cochlearis infrastructure project. The main [README.md](../README.md) in the project root provides a quick start guide and overview.

## Navigation Guide

### Getting Started

| Document | Purpose |
|----------|---------|
| [DEPLOY.md](DEPLOY.md) | Step-by-step deployment instructions for each environment |
| [RECIPE.md](RECIPE.md) | Complete infrastructure setup recipe from scratch |

### Operations & Troubleshooting

| Document | Purpose |
|----------|---------|
| [GOTCHAS.md](GOTCHAS.md) | Troubleshooting guide and lessons learned — **start here when something breaks** |
| [MANAGEMENT.md](MANAGEMENT.md) | Service-specific admin access, user management, and day-to-day operations |
| [OIDC.md](OIDC.md) | OIDC/SSO troubleshooting history (Zitadel integration — on hold) |

### Architecture & Planning

| Document | Purpose |
|----------|---------|
| [COST.md](COST.md) | Detailed cost analysis with resource sizing rationale |
| [PHOENIX.md](PHOENIX.md) | Gap analysis for destroy/rebuild capability ("phoenix architecture") |
| [PRODUCTIONREADINESS.md](PRODUCTIONREADINESS.md) | Production readiness checklist and assessment |
| [EXCELLENCE.md](EXCELLENCE.md) | Principles and philosophy behind the repository structure |

### Service-Specific

| Document | Purpose |
|----------|---------|
| [ZULIP.md](ZULIP.md) | Zulip-specific documentation (EC2 deployment, not ECS) |
| [DOCUSAURUS_DEPLOYMENT.md](DOCUSAURUS_DEPLOYMENT.md) | Docusaurus static site deployment details |

### Development & Maintenance

| Document | Purpose |
|----------|---------|
| [TODOs.md](TODOs.md) | Outstanding tasks and planned improvements |
| [GUIDERAILS.md](GUIDERAILS.md) | Operational constraints and safety guidelines for AI/LLM assistance |
| [AGENTEXPERT.md](AGENTEXPERT.md) | Future plans for GitHub Custom Agents (`.agent.md` files) |

### Temporary/Working Files

| Document | Purpose |
|----------|---------|
| [gpg.md](gpg.md) | GPG key troubleshooting notes (temporary) |

## Quick Links by Task

**"I need to deploy the infrastructure"** → Start with [DEPLOY.md](DEPLOY.md)

**"Something is broken"** → Check [GOTCHAS.md](GOTCHAS.md) first, then [MANAGEMENT.md](MANAGEMENT.md)

**"How much will this cost?"** → See [COST.md](COST.md)

**"Can we destroy and rebuild everything?"** → Read [PHOENIX.md](PHOENIX.md) for the gap analysis

**"How do I manage users in BookStack/Zulip/Outline?"** → See [MANAGEMENT.md](MANAGEMENT.md)

**"Why doesn't OIDC work?"** → See [OIDC.md](OIDC.md) — TL;DR: it's on hold, use Azure AD/Google OAuth instead
