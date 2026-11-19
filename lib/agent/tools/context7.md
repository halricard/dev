### Documentation: Context7 (`dev-context7`)

- Phases: context, design and execute. Look up the documentation before you write or change code that uses {{APP_TITLE}} APIs, hooks, configuration or CLI commands, and before you add or upgrade a package. Do not rely on memory for APIs that change between versions.
- Use the library IDs in the notes below and pass them straight to `query-docs`. Call `resolve-library-id` only for other packages, such as a Composer or npm dependency of this project.
- Ask one specific question per `query-docs` call. Match the documentation to the version above: when an ID accepts a version (`/org/project/version`), use the one this project runs.
- Follow what the documentation says over what you remember. If it contradicts the code in this project, trust the code and mention the difference.
