# frozen_string_literal: true
require "time"
require "yaml"

module LoreReleaseTooling
  class Error < StandardError; end
  class PreflightFailed < Error; end

  FULL_SHA = /\A[0-9a-f]{40}\z/i

  module_function

  def project_release_settings(path)
    targets = YAML.load_file(path).fetch("targets")
    settings = %w[Lore LoreWidget].map { |name| targets.fetch(name).fetch("settings").fetch("base") }
    versions = settings.map { |value| value.fetch("MARKETING_VERSION").to_s }.uniq
    floors = settings.map { |value| value.fetch("CURRENT_PROJECT_VERSION").to_s }.uniq
    raise Error, "App and widget release versions/build floors must match." unless versions.length == 1 && floors.length == 1
    { version: versions.first, build_floor: positive_build!(floors.first) }
  end

  def release_version!(value, project_version:)
    version = value.to_s.strip
    unless version.match?(/\A\d+(?:\.\d+)*\z/) && version == project_version.to_s
      raise Error, "expected_version must exactly match project.yml marketing version #{project_version}."
    end
    version
  end

  def positive_build!(value)
    text = value.to_s
    raise Error, "Build number must be a positive integer." unless text.match?(/\A[1-9]\d*\z/)
    text.to_i
  end

  def next_build_number(project_floor:, latest:)
    floor = positive_build!(project_floor)
    text = latest.to_s
    raise Error, "Latest TestFlight build must be a nonnegative integer." unless text.match?(/\A\d+\z/)
    [floor, text.to_i + 1].max
  end

  def version_for_preparation!(versions, expected_version:, editable_version:)
    matches = Array(versions).select { |version| version.platform == "IOS" && version.version_string == expected_version }
    raise Error, "Multiple iOS records for version #{expected_version}." if matches.length > 1
    if matches.empty? && editable_version
      raise Error, "Refusing to rename editable version #{editable_version.version_string}; requested #{expected_version}."
    end
    matches.first
  end

  def verify_review_item_versions!(version_ids, expected_version_id:)
    unless version_ids == [expected_version_id]
      raise Error, "Review submission must contain exactly the expected App Store version item; found #{version_ids.inspect}."
    end
    true
  end

  class ReleaseTarget
    attr_reader :version, :build_number

    def initialize(expected_version:, expected_build:, project_version:, build_floor:)
      @version = LoreReleaseTooling.release_version!(expected_version, project_version: project_version)
      @build_number = expected_build.to_s.strip
      number = LoreReleaseTooling.positive_build!(@build_number)
      raise Error, "Expected build is below project.yml release floor #{build_floor}." if number < build_floor
    end

    def verify_version!(record)
      unless record && record.version_string == version && record.platform == "IOS"
        raise Error, "Refusing release action: expected iOS version #{version}."
      end
      record
    end

    def verify_build!(build, app_id:, now: Time.now)
      unless build && build.version.to_s == build_number && build.app_version == version &&
             build.app_id.to_s == app_id.to_s && build.platform == "IOS"
        raise Error, "Refusing release action: expected this app's iOS #{version} (#{build_number})."
      end
      unless build.processing_state == "VALID" && build.expired == false
        raise Error, "Expected build #{build_number} must be VALID and explicitly nonexpired."
      end
      unless build.expiration_date.to_s.empty?
        begin
          expiry = Time.iso8601(build.expiration_date)
        rescue ArgumentError
          raise Error, "Expected build has an invalid expiration date."
        end
        raise Error, "Expected build #{build_number} has expired." unless expiry > now
      end
      build
    end

    def select_build!(builds, app_id:)
      matches = Array(builds).select { |build| build.version.to_s == build_number && build.app_version == version }
      raise Error, "Expected exactly one build for #{version} (#{build_number}); found #{matches.length}." unless matches.length == 1
      verify_build!(matches.first, app_id: app_id)
    end
  end

  # The pinned client exposes raw GET responses even for product resources
  # that have no Spaceship model. No price or product mutation is performed.
  def product_catalog(client, app_id:)
    rows = lambda do |path|
      client.get(path, { limit: 200 }).all_pages.flat_map do |response|
        data = response.body.fetch("data")
        raise Error, "Malformed product catalog response." unless data.is_a?(Array)
        data
      end
    end
    groups = rows.call("v1/apps/#{app_id}/subscriptionGroups")
    subscriptions = groups.flat_map { |group| rows.call("v1/subscriptionGroups/#{group.fetch('id')}/subscriptions") }
    purchases = rows.call("v1/apps/#{app_id}/inAppPurchasesV2")
    (subscriptions + purchases).map do |row|
      attributes = row.fetch("attributes")
      { id: row.fetch("id"), type: row.fetch("type"), product_id: attributes.fetch("productId"),
        state: attributes.fetch("state"), name: attributes["name"] }
    end
  end

  def review_hold_enabled!(environment = ENV)
    value = environment.fetch("APP_REVIEW_HOLD", "").to_s.strip.downcase
    unless %w[true false].include?(value)
      raise Error,
            "APP_REVIEW_HOLD must be explicitly true or false in the app-store-production environment."
    end

    value == "true"
  end

  def ensure_release_mutation_allowed!(environment = ENV)
    return true unless review_hold_enabled!(environment)

    raise Error, "App Review is held. Set APP_REVIEW_HOLD=false before changing the App Store release."
  end

  def ensure_review_hold_action_allowed!(environment = ENV)
    return true if review_hold_enabled!(environment)

    raise Error,
          "APP_REVIEW_HOLD must be true in the app-store-production environment before cancelling review."
  end

  class PreflightReporter
    attr_reader :failures

    def initialize(&emitter)
      raise ArgumentError, "an emitter block is required" unless block_given?

      @emitter = emitter
      @failures = []
    end

    def record(status, label, detail)
      normalized_status = status.to_s.upcase
      rendered_label = label.to_s
      rendered_detail = detail.to_s
      @failures << "#{rendered_label}: #{rendered_detail}" if normalized_status == "FAIL"
      @emitter.call(normalized_status, rendered_label, rendered_detail)
    end

    def verify!
      return true if failures.empty?

      noun = failures.length == 1 ? "finding" : "findings"
      raise PreflightFailed,
            "App Store preflight found #{failures.length} blocking #{noun}: #{failures.join(' | ')}"
    end
  end

  class GitRepository
    def initialize(path)
      @path = File.expand_path(path)
    end

    def commit_exists?(sha)
      system(
        "git", "cat-file", "-e", "#{sha}^{commit}",
        chdir: @path, out: File::NULL, err: File::NULL,
      )
    end

    def ancestor_of_head?(sha)
      system(
        "git", "merge-base", "--is-ancestor", sha, "HEAD",
        chdir: @path, out: File::NULL, err: File::NULL,
      )
    end
  end

  class ScreenshotProvenance
    def initialize(source_sha_path:, release_source_sha:, repository:)
      @source_sha_path = source_sha_path
      @release_source_sha = release_source_sha.to_s.strip
      @repository = repository
    end

    def verify!
      unless File.exist?(@source_sha_path)
        raise Error,
              "Missing fastlane/promo_screenshots/SOURCE_SHA. Regenerate screenshots from the release commit."
      end

      screenshot_sha = File.read(@source_sha_path).strip
      validate_full_sha!(screenshot_sha, "Screenshot SOURCE_SHA")
      validate_full_sha!(@release_source_sha, "RELEASE_SOURCE_SHA")

      unless screenshot_sha.casecmp?(@release_source_sha)
        raise Error,
              "Screenshots were captured from #{screenshot_sha}, not the requested release source " \
              "#{@release_source_sha}. Regenerate every screenshot from the exact release source."
      end

      unless @repository.commit_exists?(@release_source_sha)
        raise Error,
              "Cannot verify release source #{@release_source_sha}: the commit is not in this clone. " \
              "Check out with fetch-depth: 0."
      end

      unless @repository.ancestor_of_head?(@release_source_sha)
        raise Error,
              "Release source #{@release_source_sha} is not an ancestor of this checkout. " \
              "Refusing to use screenshots from a divergent release."
      end

      true
    end

    private

    def validate_full_sha!(sha, label)
      return if sha.match?(FULL_SHA)

      raise Error, "#{label} must be an explicit 40-character Git commit SHA."
    end
  end
end
