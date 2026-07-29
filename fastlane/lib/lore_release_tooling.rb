# frozen_string_literal: true

module LoreReleaseTooling
  class Error < StandardError; end
  class PreflightFailed < Error; end

  FULL_SHA = /\A[0-9a-f]{40}\z/i

  module_function

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
