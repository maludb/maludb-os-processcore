"""processcore_actions_mcp: the localhost-only actions server (navigation, voice actions, undo).

Every write goes through the app's own PHP endpoints with the per-message action
token minted by PHP (header X-Action-Token on the MCP request). See docs/09.
"""
