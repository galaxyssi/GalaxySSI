# GalaxySSI Connector Status

GalaxySSI Desktop exposes local capabilities as mobile contacts.

## Default Connectors

- Hermes Agent
- Codex Agent
- Claude Code
- Local LLM
- Custom Agent

## Connector Matrix

The connector matrix tracks readiness, local proof, mobile delivery, and the next setup action for each contact.

Protocol: GalaxySSI Link Protocol v1.0.3

## Collaborative File Safety

Desktop records task-scoped Agent read sets and write sets. A write that changes
a file observed by another Agent creates a durable conflict notice. The affected
Agent receives bounded, untrusted conflict context and must refresh the file
before continuing. Route, conversation, task, repository, and workspace scopes
remain isolated, and only relative file paths are persisted.

## Checks

```bash
npm run check
npm run smoke
npm run smoke:e2e
```

## Packaged Smoke

```bash
npm run package:win:python
npm run smoke:packaged
```
