### Design files: Penpot (`penpot`)

- Phases: design, execute and verify. When the issue or the spec links a Penpot file or board, read it through the `penpot` server before you design the screen: structure, components, colours, typography and an export of the board.
- When the user asks for a draft of a new screen, you can draw it in the open Penpot file before you write code, then ask for approval.
- Map each element of the board to the components and tokens {{APP_TITLE}} already uses (see the UI notes below). Record any difference as an assumption in the spec or the design.
- In verify, compare each screen you built with its board.
- The server only works while the user keeps a Penpot tab open with the MCP plugin connected (File → MCP Server → Connect), and it acts on the page focused in that tab. If its tools fail, ask the user to reconnect the plugin.
- The key comes from the `PENPOT_MCP_KEY` environment variable. Never print, store or ask for it. If the server fails to authenticate, tell the user to run `dev agent key penpot`, open a new terminal and restart Claude Code.
