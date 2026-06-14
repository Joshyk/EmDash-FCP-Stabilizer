# Tests

Run the standalone active-library resolver regression tests with:

```sh
scripts/run_active_library_resolver_tests.sh
```

These tests do not open Final Cut Pro, read the user's Final Cut Pro preferences, or touch
real `.fcpbundle` libraries. They create fake `.fcpbundle` directories, fake Event folders,
and `CurrentVersion.flexolibrary` SQLite fixtures under a new temporary directory on each
run. The fixture is intentionally left in place so the test does not delete anything from
the local machine.
