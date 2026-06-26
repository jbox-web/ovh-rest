# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `#patch` verb.
- `#request_consumer_key` to start the OVH credential flow (`POST /auth/credential`).
- `#synchronize_time!` and the `auto_sync_time:` option to handle clock skew via OVH's `/auth/time` endpoint.
- `timeout:` and `open_timeout:` options (defaults: 30s / 10s).
- `OvhRest::Error` and `OvhRest::ApiError` (exposing `message`, `error_code`, `http_code`, `status`, `response`); the gem no longer leaks Faraday exceptions.
- Credential headers (`X-Ovh-Application`, `X-Ovh-Consumer`, `X-Ovh-Signature`) are now redacted from logger output.
- `client:` constructor option to inject a Faraday connection.

### Changed

- **Breaking:** `GET`/`DELETE` parameters are now sent as a URL query string instead of a JSON body, and empty parameters produce an empty body (instead of `{}`), matching the OVH signing convention.
- **Breaking:** removed the public `client=` writer; inject via the `client:` constructor option instead.
- Renamed the internal `OvhRest::Client::VERSION` constant to `API_VERSION` to avoid clashing with the gem version.
