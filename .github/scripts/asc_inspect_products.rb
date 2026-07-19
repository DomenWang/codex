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
  uri.query = URI.encode_www_form(params) unless params.empty?
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{token}"
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end
  unless response.is_a?(Net::HTTPSuccess)
    warn "ASC GET #{path} failed: #{response.code} #{response.message}"
    warn response.body
    exit 1
  end
  JSON.parse(response.body)
end

def compact_resource(item)
  {
    id: item["id"],
    type: item["type"],
    reference_name: item.dig("attributes", "referenceName"),
    product_id: item.dig("attributes", "productId"),
    family_sharable: item.dig("attributes", "familySharable"),
    state: item.dig("attributes", "state"),
    subscription_period: item.dig("attributes", "subscriptionPeriod"),
    review_note_present: !item.dig("attributes", "reviewNote").to_s.strip.empty?
  }.compact
end

app_id = ENV.fetch("ASC_APP_ID")

in_app_purchases = asc_get(
  "/v1/apps/#{app_id}/inAppPurchasesV2",
  {
    "include" => "inAppPurchaseLocalizations,appStoreReviewScreenshot",
    "limit" => "200"
  },
  token
)

subscription_groups = asc_get(
  "/v1/apps/#{app_id}/subscriptionGroups",
  {
    "include" => "subscriptionGroupLocalizations",
    "limit" => "200"
  },
  token
)

subscriptions = subscription_groups.fetch("data", []).flat_map do |group|
  response = asc_get(
    "/v1/subscriptionGroups/#{group.fetch("id")}/subscriptions",
    {
      "include" => "subscriptionLocalizations,appStoreReviewScreenshot",
      "limit" => "200"
    },
    token
  )
  response.fetch("data", []).map do |subscription|
    compact_resource(subscription).merge(subscription_group_id: group.fetch("id"))
  end
end

summary = {
  in_app_purchases: in_app_purchases.fetch("data", []).map { |item| compact_resource(item) },
  in_app_purchase_related: in_app_purchases.fetch("included", []).map do |item|
    {
      id: item["id"],
      type: item["type"],
      locale: item.dig("attributes", "locale"),
      name: item.dig("attributes", "name"),
      description_present: !item.dig("attributes", "description").to_s.strip.empty?,
      screenshot_state: item.dig("attributes", "assetDeliveryState", "state")
    }.compact
  end,
  subscription_groups: subscription_groups.fetch("data", []).map { |item| compact_resource(item) },
  subscription_group_localizations: subscription_groups.fetch("included", []).map do |item|
    {
      id: item["id"],
      locale: item.dig("attributes", "locale"),
      name: item.dig("attributes", "name"),
      state: item.dig("attributes", "state")
    }.compact
  end,
  subscriptions: subscriptions
}

puts JSON.pretty_generate(summary)
