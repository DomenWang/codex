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

def asc_request(method, path, token, params: {}, body: nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  uri.query = URI.encode_www_form(params) unless params.empty?
  request_class = {
    get: Net::HTTP::Get,
    patch: Net::HTTP::Patch
  }.fetch(method)
  request = request_class.new(uri)
  request["Authorization"] = "Bearer #{token}"
  if body
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body)
  end
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end
  unless response.is_a?(Net::HTTPSuccess)
    warn "ASC #{method.upcase} #{path} failed: #{response.code} #{response.message}"
    warn response.body
    exit 1
  end
  response.body.nil? || response.body.empty? ? {} : JSON.parse(response.body)
end

app_id = ENV.fetch("ASC_APP_ID")
version_string = ENV.fetch("ASC_VERSION")
build_number = ENV.fetch("ASC_BUILD")

build = nil
40.times do |attempt|
  builds = asc_request(
    :get,
    "/v1/builds",
    token,
    params: {
      "filter[app]" => app_id,
      "filter[version]" => build_number,
      "limit" => "10"
    }
  )
  build = builds.fetch("data", []).find do |item|
    item.dig("attributes", "processingState") == "VALID" &&
      item.dig("attributes", "expired") != true
  end
  break if build

  puts "Build #{build_number} is still processing (#{attempt + 1}/40)"
  sleep 30
end
abort("Build #{build_number} did not become VALID in time") unless build

versions = asc_request(
  :get,
  "/v1/apps/#{app_id}/appStoreVersions",
  token,
  params: {
    "filter[versionString]" => version_string,
    "filter[platform]" => "IOS",
    "limit" => "10"
  }
)
version = versions.fetch("data", []).first
abort("App Store version #{version_string} was not found") unless version
version_id = version.fetch("id")

submissions = asc_request(
  :get,
  "/v1/apps/#{app_id}/reviewSubmissions",
  token,
  params: {
    "filter[platform]" => "IOS",
    "limit" => "50"
  }
)
active_submission = submissions.fetch("data", []).find do |item|
  %w[WAITING_FOR_REVIEW IN_REVIEW].include?(item.dig("attributes", "state"))
end

if active_submission
  submission_id = active_submission.fetch("id")
  asc_request(
    :patch,
    "/v1/reviewSubmissions/#{submission_id}",
    token,
    body: {
      data: {
        type: "reviewSubmissions",
        id: submission_id,
        attributes: {
          canceled: true
        }
      }
    }
  )
  puts "Canceled review submission #{submission_id} so Build #{build_number} can replace it"
end

40.times do
  current = asc_request(:get, "/v1/appStoreVersions/#{version_id}", token)
  state = current.dig("data", "attributes", "appStoreState")
  break unless %w[WAITING_FOR_REVIEW IN_REVIEW].include?(state)

  puts "Waiting for App Store version to leave #{state}"
  sleep 15
end

asc_request(
  :patch,
  "/v1/appStoreVersions/#{version_id}/relationships/build",
  token,
  body: {
    data: {
      type: "builds",
      id: build.fetch("id")
    }
  }
)

puts "Attached VALID Build #{build_number} to App Store version #{version_string}"
