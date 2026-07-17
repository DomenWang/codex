#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "jwt"
require "net/http"
require "openssl"
require "uri"

key_id = ENV.fetch("APPLE_API_KEY_ID")
issuer_id = ENV.fetch("APPLE_API_ISSUER_ID")
private_key = OpenSSL::PKey.read(Base64.decode64(ENV.fetch("APPLE_API_KEY_BASE64")))
now = Time.now.to_i
token = JWT.encode(
  { iss: issuer_id, iat: now, exp: now + 1_200, aud: "appstoreconnect-v1" },
  private_key,
  "ES256",
  { kid: key_id, typ: "JWT" }
)

def asc_get(path, params, token)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  uri.query = URI.encode_www_form(params)
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{token}"
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end
  unless response.is_a?(Net::HTTPSuccess)
    warn "ASC request failed: #{response.code} #{response.message}"
    warn response.body
    exit 1
  end
  JSON.parse(response.body)
end

app_id = ENV.fetch("ASC_APP_ID")
version_string = ENV.fetch("ASC_VERSION")
build_number = ENV.fetch("ASC_BUILD")

builds = asc_get(
  "/v1/builds",
  {
    "filter[app]" => app_id,
    "filter[version]" => version_string,
    "filter[buildNumber]" => build_number,
    "include" => "preReleaseVersion",
    "limit" => "10"
  },
  token
)

versions = asc_get(
  "/v1/appStoreVersions",
  {
    "filter[app]" => app_id,
    "filter[versionString]" => version_string,
    "filter[platform]" => "IOS",
    "include" => "build,appStoreVersionLocalizations,appStoreReviewDetail",
    "limit" => "10"
  },
  token
)

summary = {
  requested: { app_id: app_id, version: version_string, build: build_number },
  builds: builds.fetch("data", []).map do |item|
    {
      id: item["id"],
      version: item.dig("attributes", "version"),
      processing_state: item.dig("attributes", "processingState"),
      uploaded_date: item.dig("attributes", "uploadedDate"),
      expired: item.dig("attributes", "expired")
    }
  end,
  app_store_versions: versions.fetch("data", []).map do |item|
    {
      id: item["id"],
      state: item.dig("attributes", "appStoreState"),
      version_string: item.dig("attributes", "versionString"),
      platform: item.dig("attributes", "platform"),
      build_id: item.dig("relationships", "build", "data", "id")
    }
  end,
  included: versions.fetch("included", []).map do |item|
    {
      type: item["type"],
      id: item["id"],
      locale: item.dig("attributes", "locale"),
      support_url: item.dig("attributes", "supportUrl")
    }.compact
  end
}

puts JSON.pretty_generate(summary)
