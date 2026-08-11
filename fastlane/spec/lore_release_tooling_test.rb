# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/lore_release_tooling"

class LoreReleaseToolingTest < Minitest::Test
  class FakeRepository
    def initialize(commit_exists: true, ancestor_of_head: true)
      @commit_exists = commit_exists
      @ancestor_of_head = ancestor_of_head
    end

    def commit_exists?(_sha)
      @commit_exists
    end

    def ancestor_of_head?(_sha)
      @ancestor_of_head
    end
  end

  RELEASE_SHA = "a" * 40
  OTHER_SHA = "b" * 40

  def test_review_hold_must_be_explicit
    error = assert_raises(LoreReleaseTooling::Error) do
      LoreReleaseTooling.review_hold_enabled!({})
    end

    assert_includes error.message, "explicitly true or false"
    assert LoreReleaseTooling.review_hold_enabled!("APP_REVIEW_HOLD" => " TRUE ")
    refute LoreReleaseTooling.review_hold_enabled!("APP_REVIEW_HOLD" => "false")
  end

  def test_release_mutations_fail_closed_while_review_is_held
    assert_raises(LoreReleaseTooling::Error) do
      LoreReleaseTooling.ensure_release_mutation_allowed!("APP_REVIEW_HOLD" => "true")
    end
    assert LoreReleaseTooling.ensure_release_mutation_allowed!("APP_REVIEW_HOLD" => "false")
  end

  def test_review_cancellation_requires_the_hold
    assert LoreReleaseTooling.ensure_review_hold_action_allowed!("APP_REVIEW_HOLD" => "true")
    assert_raises(LoreReleaseTooling::Error) do
      LoreReleaseTooling.ensure_review_hold_action_allowed!("APP_REVIEW_HOLD" => "false")
    end
  end

  def test_preflight_reporter_aggregates_only_failures
    emitted = []
    reporter = LoreReleaseTooling::PreflightReporter.new do |status, label, detail|
      emitted << [status, label, detail]
    end

    reporter.record("WARN", "Manual privacy", "inspect in App Store Connect")
    reporter.record("FAIL", "Build", "missing")
    reporter.record("FAIL", "Screenshots", "missing")

    error = assert_raises(LoreReleaseTooling::PreflightFailed) { reporter.verify! }
    assert_includes error.message, "2 blocking findings"
    assert_includes error.message, "Build: missing"
    assert_includes error.message, "Screenshots: missing"
    assert_equal 3, emitted.length
  end

  def test_preflight_reporter_allows_warnings_without_a_false_failure
    reporter = LoreReleaseTooling::PreflightReporter.new { |_status, _label, _detail| }
    reporter.record("WARN", "IAP", "manual")

    assert reporter.verify!
  end

  def test_screenshot_provenance_requires_exact_release_source
    with_source_sha(OTHER_SHA) do |path|
      error = assert_raises(LoreReleaseTooling::Error) do
        provenance(path: path, release_sha: RELEASE_SHA).verify!
      end

      assert_includes error.message, "not the requested release source"
    end
  end

  def test_screenshot_provenance_rejects_implicit_or_abbreviated_sha
    with_source_sha(RELEASE_SHA) do |path|
      error = assert_raises(LoreReleaseTooling::Error) do
        provenance(path: path, release_sha: "").verify!
      end
      assert_includes error.message, "40-character"

      error = assert_raises(LoreReleaseTooling::Error) do
        provenance(path: path, release_sha: RELEASE_SHA[0, 12]).verify!
      end
      assert_includes error.message, "40-character"
    end
  end

  def test_screenshot_provenance_requires_known_nondivergent_commit
    with_source_sha(RELEASE_SHA) do |path|
      unknown = provenance(
        path: path,
        release_sha: RELEASE_SHA,
        repository: FakeRepository.new(commit_exists: false),
      )
      assert_raises(LoreReleaseTooling::Error) { unknown.verify! }

      divergent = provenance(
        path: path,
        release_sha: RELEASE_SHA,
        repository: FakeRepository.new(ancestor_of_head: false),
      )
      assert_raises(LoreReleaseTooling::Error) { divergent.verify! }
    end
  end

  def test_screenshot_provenance_accepts_exact_known_ancestor
    with_source_sha(RELEASE_SHA) do |path|
      assert provenance(path: path, release_sha: RELEASE_SHA).verify!
    end
  end

  def test_all_release_mutation_lanes_are_guarded_before_authentication
    expectations = {
      "screenshots_upload" => "app_store_connect_api_key",
      "submit_for_review" => "asc_token!",
      "swap_latest_build_and_resubmit" => "asc_token!",
      "set_auto_release" => "asc_token!",
    }

    expectations.each do |lane, authentication_call|
      body = lane_body(lane)
      guard = body.index("ensure_app_store_release_mutation_allowed!")
      authentication = body.index(authentication_call)
      refute_nil guard, "#{lane} must enforce APP_REVIEW_HOLD"
      refute_nil authentication, "#{lane} authentication call changed; update this contract test"
      assert_operator guard, :<, authentication, "#{lane} must fail before contacting App Store Connect"
    end
  end

  def test_known_app_store_mutation_calls_cannot_hide_in_an_unguarded_lane
    mutation_markers = [
      "upload_to_app_store(",
      "create_review_submission(",
      "add_app_store_version_to_review_items(",
      ".submit_for_review",
      ".select_build(",
      "releaseType:",
    ]
    mutating_lanes = all_lane_bodies.each_with_object([]) do |(name, body), lanes|
      lanes << name if mutation_markers.any? { |marker| body.include?(marker) }
    end

    assert_equal(
      %w[screenshots_upload set_auto_release submit_for_review swap_latest_build_and_resubmit],
      mutating_lanes.sort,
    )
    mutating_lanes.each do |lane|
      assert_includes lane_body(lane), "ensure_app_store_release_mutation_allowed!"
    end
  end

  def test_submission_actions_require_screenshot_provenance_but_preflight_does_not
    %w[screenshots_upload submit_for_review swap_latest_build_and_resubmit].each do |lane|
      assert_includes lane_body(lane), "verify_submission_screenshot_provenance!"
    end

    preflight = lane_body("preflight")
    refute_includes preflight, "verify_submission_screenshot_provenance!"
    refute_includes preflight, "ensure_app_store_release_mutation_allowed!"
    assert_includes preflight, "verify_preflight!(reporter)"
  end

  def test_manual_preflight_surfaces_remain_explicit_warnings
    preflight = lane_body("preflight")

    assert_match(/"WARN", "Subscriptions"/, preflight)
    assert_match(/"WARN", "Privacy labels"/, preflight)
    assert_match(/"WARN", "EU trader status"/, preflight)
    assert_match(/"WARN", "Manual-only checks"/, preflight)
  end

  def test_hold_review_uses_the_protective_guard_before_authentication
    body = lane_body("hold_review")
    guard = body.index("ensure_review_hold_action_allowed!")
    authentication = body.index("asc_token!")

    refute_nil guard
    refute_nil authentication
    assert_operator guard, :<, authentication
    refute_includes body, "ensure_app_store_release_mutation_allowed!"
  end

  def test_swap_latest_waits_for_review_cancellation_before_selecting_build
    body = lane_body("swap_latest_build_and_resubmit")
    cancel = body.index("existing.cancel_submission")
    wait = body.index("wait_for_review_cancellation!")
    select = body.index("version.select_build")

    refute_nil cancel
    refute_nil wait
    refute_nil select
    assert_operator cancel, :<, wait
    assert_operator wait, :<, select
    assert_includes body, "prepare_review_submission_for_version!"
  end

  def test_submission_helper_uses_ready_review_submission_and_item_verification
    fastfile = File.read(File.expand_path("../Fastfile", __dir__))

    assert_includes fastfile, "get_ready_review_submission"
    assert_includes fastfile, "wait_for_review_submission_item!"
    refute_match(/get_in_progress_review_submission\\(platform: platform\\)\\n\\s*submission = app.create_review_submission/, fastfile)
  end

  private

  def provenance(path:, release_sha:, repository: FakeRepository.new)
    LoreReleaseTooling::ScreenshotProvenance.new(
      source_sha_path: path,
      release_source_sha: release_sha,
      repository: repository,
    )
  end

  def with_source_sha(sha)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "SOURCE_SHA")
      File.write(path, "#{sha}\n")
      yield path
    end
  end

  def lane_body(name)
    all_lane_bodies.fetch(name) { flunk "Fastlane lane #{name} is missing" }
  end

  def all_lane_bodies
    lines = File.readlines(File.expand_path("../Fastfile", __dir__))
    starts = lines.each_index.select { |index| lines[index].match?(/^  lane :\w+\b/) }
    starts.to_h do |start|
      name = lines[start].match(/^  lane :(\w+)\b/)[1]
      finish = ((start + 1)...lines.length).find do |index|
        lines[index].match?(/^  desc /) || lines[index].match?(/^end\s*$/)
      end
      [name, lines[start...(finish || lines.length)].join]
    end
  end
end
