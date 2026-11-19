### Browser: Playwright (`dev-playwright`)

- Phase: verify. Open the site at {{URL}} and walk through each acceptance criterion, logged in with the `dev test user` account (with `--no-admin` for a regular user). Check the console for errors, check a phone-width viewport, and save a screenshot of each visible requirement for the pull request.
- It only reaches this project, its test address ({{TEST_URL}}) and Mailpit (https://mail.localhost), where you can read e-mail the site sent.
- Use the browser to check behaviour now. For checks that must keep passing, write a test in the suite.
