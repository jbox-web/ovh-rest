# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Role

You are an expert Ruby developer: meticulous, precise, and exhaustive. Favor idiomatic, well-tested code, handle edge cases, and never cut corners.

You always work in TDD: write a failing test first, watch it fail, then write the minimal code to make it pass, then refactor. No production code without a failing test first.

## Overview

`ovh-rest` is a tiny Ruby gem wrapping the OVH REST API. It handles OVH's request-signing authentication on top of [Faraday](https://github.com/lostisland/faraday), exposing a thin HTTP client. The entire public surface is `OvhRest::Client` in `lib/ovh_rest/client.rb`.

## Commands

```bash
bin/rspec                              # run the full test suite
bin/rspec spec/ovh_rest/client_spec.rb # run one file
bin/rspec spec/ovh_rest/client_spec.rb:52  # run one example by line
bin/rubocop                            # lint (must pass in CI)
bin/rubocop -a                         # auto-correct safe offenses
bundle exec rake                       # default task == spec
bin/guard                              # auto-run specs on file change
```

CI (`.github/workflows/ci.yml`) runs Rubocop on Ruby 3.2 and RSpec across Ruby 3.2–4.0, JRuby, and TruffleRuby. `required_ruby_version` is `>= 3.2.0`.

## Architecture

- **Autoloading via Zeitwerk** (`lib/ovh_rest.rb`). The gem requires `ovh-rest` (dash) which requires `ovh_rest` (underscore); the dash file is `ignore`d by the loader and excluded from Rubocop. Add new classes under `lib/ovh_rest/` and they autoload by convention — no manual `require`.
- **HTTP verb methods are generated** via `class_eval` in a loop over `%w[get post put delete]`. Each delegates to `#query`, which builds signed headers and calls `Faraday#run_request`. To change request behavior, edit `#query` / `#build_headers`, not individual verb methods.
- **OVH authentication** is in `#compute_signature`: `$1$` + SHA1 of `application_secret+consumer_key+METHOD+full_url+body+timestamp`. The signed URL must match the actual request URL exactly (including `/{api_version}/` prefix and normalized path), or OVH rejects the call. `#normalize_path` strips a leading `/` so callers may pass paths with or without it.
- Responses are parsed JSON (Faraday `:json` response middleware); `4xx/5xx` raise via `:raise_error` middleware.

## Testing

Tests inject a stubbed Faraday connection through the `attr_writer :client` (`o.client = conn`) using `Faraday::Adapter::Test::Stubs` — this is the seam for testing without hitting the network. The `after` hook resets `Faraday.default_connection` so stubs don't leak between examples. RSpec runs with random order, zero-monkey-patching, and `raise_errors_for_deprecations!`.
