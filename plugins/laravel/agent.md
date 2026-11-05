## Laravel

- Run Artisan with `dev exec php artisan <command>`. Run Composer with `dev exec composer <command>`.
- Run migrations with `dev exec php artisan migrate`. Take a `dev snapshot` first.
- Inspect data with `dev exec php artisan tinker --execute="..."` or `dev db query "..."`.
- The queue worker (`queue:listen`) and Vite (`npm run dev`) start with `dev up` through `dev.workers`. Check them with `dev worker`.
- The scheduler (`schedule:run`) runs every 60 seconds from `dev.schedule`. Check it with `dev schedule`.
- The database settings in `.env` come from `dev`. Do not hard-code credentials.
- Run tests with `dev exec php artisan test`. Install frontend packages with `dev exec npm install`.
