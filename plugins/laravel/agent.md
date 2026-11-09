## Laravel

- Run Artisan with `dev exec php artisan <command>`. Run Composer with `dev exec composer <command>`.
- Run migrations with `dev exec php artisan migrate`. Take a `dev snapshot` first.
- Inspect data with `dev exec php artisan tinker --execute="..."` or `dev db query "..."`.
- The queue worker (`queue:listen`) and Vite (`npm run dev`) start with `dev up` through `dev.workers`. Check them with `dev worker`.
- The scheduler (`schedule:run`) runs every 60 seconds from `dev.schedule`. Check it with `dev schedule`.
- The database settings in `.env` come from `dev`. Do not hard-code credentials.
- Install frontend packages with `dev exec npm install`.

### Laravel tests

- `dev test pest [args]` (or `dev test phpunit` in projects without Pest) runs `php artisan test`. Example: `dev test pest --filter=UserTest`. Tests live in `tests/Feature` and `tests/Unit`.
- `dev test browser [args]` runs Pest 4 browser tests (`pestphp/pest-plugin-browser`). Pest serves the app itself, so it does not need `dev up`. Browser tests live in `tests/Browser` and use `visit('/')`.

### Laravel documentation

- `/laravel/docs/<major>.x` — the Laravel guides for this project's version (for example `/laravel/docs/12.x`). Use it for routing, Eloquent, validation, queues, Artisan and configuration.
- `/laravel/framework` — the framework source, for exact class and method signatures.
- `/pestphp/docs` — Pest, including browser tests.
- Look up first-party packages (Livewire, Inertia, Sanctum, Horizon, Filament) with `resolve-library-id`, using the version in `composer.lock`.
