### Repository: GitHub (`github`)

- Phases: context and deliver. In context, read the issue, its comments and the linked pull requests, then create the branch.
- In deliver, open the pull request with a table of requirements and the tests that cover them, the screenshots from verify and `Closes #<issue>`. Read the review comments and treat each one as a new task.
- `dev` hands the stored token to the server. Never print, store or ask for it. If the server fails to start or to authenticate, tell the user to run `dev agent key github`, then reconnect it with `/mcp`.
