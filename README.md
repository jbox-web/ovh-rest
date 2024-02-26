# OVH Rest client

[![GitHub license](https://img.shields.io/github/license/jbox-web/ovh-rest.svg)](https://github.com/jbox-web/ovh-rest/blob/master/LICENSE)
[![GitHub release](https://img.shields.io/github/release/jbox-web/ovh-rest.svg)](https://github.com/jbox-web/ovh-rest/releases/latest)
[![CI](https://github.com/jbox-web/ovh-rest/workflows/CI/badge.svg)](https://github.com/jbox-web/ovh-rest/actions)
[![Code Climate](https://codeclimate.com/github/jbox-web/ovh-rest/badges/gpa.svg)](https://codeclimate.com/github/jbox-web/ovh-rest)
[![Test Coverage](https://codeclimate.com/github/jbox-web/ovh-rest/badges/coverage.svg)](https://codeclimate.com/github/jbox-web/ovh-rest/coverage)

OVH Rest client is a tiny helper library based on [faraday](https://github.com/lostisland/faraday), wrapping the authentication parts and simplifying interaction with OVH API in Ruby programs.

## Installation

Put this in your `Gemfile` :

```ruby
git_source(:github){ |repo_name| "https://github.com/#{repo_name}.git" }

gem 'ovh', github: 'jbox-web/ovh-rest', tag: '1.0.0'
```

then run `bundle install`.

## Usage

```ruby
require 'ovh-rest'

ovh = OvhRest::Client.new(
  application_key: <application_key>,
  application_secret: <application_secret>,
  consumer_key: <consumer_key>
)

# Get sms account status
result = ovh.get("/sms/sms-xx12345-1")

puts YAML.dump(result)
=>
{
  "status": "enable",
  "creditsLeft": 42,
  "name": "sms-xx12345-1",
  "userQuantityWithQuota": 0,
  "description": "",
[...]
}

# Send sms
result = ovh.post("/sms/sms-xx12345-1/jobs", {
  "charset" => "UTF-8",
  "class" => "phoneDisplay",
  "coding" => "7bit",
  "priority" => "high",
  "validityPeriod" => 2880
  "message" => "Dude! Disk is CRITICAL!",
  "receivers" => ["+12345678900", "+12009876543"],
  "sender" => "+12424242424",
})

puts YAML.dump(result)
=>
{
  "totalCreditsRemoved": 2,
  "ids": [
    12345,
    12346
  ]
}
```
