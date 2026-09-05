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
      "prepare_version" => "asc_token!",
      "select_release_build" => "asc_token!",
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
      "post_app_store_version(",
    ]
    mutating_lanes = all_lane_bodies.each_with_object([]) do |(name, body), lanes|
      lanes << name if mutation_markers.any? { |marker| body.include?(marker) }
    end

    assert_equal(
      %w[prepare_version screenshots_upload select_release_build set_auto_release submit_for_review swap_latest_build_and_resubmit],
      mutating_lanes.sort,
    )
    mutating_lanes.each do |lane|
      assert_includes lane_body(lane), "ensure_app_store_release_mutation_allowed!"
    end
  end

  def test_submission_actions_require_screenshot_provenance_but_preflight_does_not
    %w[screenshots_upload select_release_build set_auto_release submit_for_review swap_latest_build_and_resubmit].each do |lane|
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

  FakeVersion = Struct.new(:version_string, :platform, keyword_init: true)
  FakeBuild = Struct.new(:version, :app_version, :app_id, :platform, :processing_state, :expired, :expiration_date, keyword_init: true)

  def release_target(version: "1.2", build: "48")
    LoreReleaseTooling::ReleaseTarget.new(
      expected_version: version, expected_build: build, project_version: "1.2", build_floor: 48,
    )
  end

  def valid_build(**overrides)
    FakeBuild.new(**{
      version: "48", app_version: "1.2", app_id: "123", platform: "IOS",
      processing_state: "VALID", expired: false, expiration_date: "2099-01-01T00:00:00Z",
    }.merge(overrides))
  end

  def test_release_target_requires_explicit_project_version_and_build_floor
    [["", "48"], ["1.1", "48"], ["1.2", ""], ["1.2", "47"], ["1.2", "latest"], ["1.2", "48.0"]].each do |version, build|
      assert_raises(LoreReleaseTooling::Error) { release_target(version: version, build: build) }
    end
    assert_equal "48", release_target.build_number
  end

  def test_exact_version_guard_rejects_wrong_or_missing_platform_version
    [nil, FakeVersion.new(version_string: "1.1", platform: "IOS"),
     FakeVersion.new(version_string: "1.2", platform: "MAC_OS")].each do |version|
      assert_raises(LoreReleaseTooling::Error) { release_target.verify_version!(version) }
    end
    assert release_target.verify_version!(FakeVersion.new(version_string: "1.2", platform: "IOS"))
  end

  def test_version_preparation_creates_new_record_without_renaming_live_version
    live = FakeVersion.new(version_string: "1.1", platform: "IOS")
    assert_nil LoreReleaseTooling.version_for_preparation!([live], expected_version: "1.2", editable_version: nil)
    assert_raises(LoreReleaseTooling::Error) do
      LoreReleaseTooling.version_for_preparation!([live], expected_version: "1.2", editable_version: live)
    end
    prepared = FakeVersion.new(version_string: "1.2", platform: "IOS")
    assert_same prepared, LoreReleaseTooling.version_for_preparation!([live, prepared], expected_version: "1.2", editable_version: prepared)
    assert_raises(LoreReleaseTooling::Error) do
      LoreReleaseTooling.version_for_preparation!([prepared, prepared], expected_version: "1.2", editable_version: prepared)
    end
  end

  def test_review_submission_requires_expected_item_instead_of_any_nonempty_submission
    [[], ["older-version"], [nil], ["expected", "older-version"], ["expected", "expected"]].each do |ids|
      assert_raises(LoreReleaseTooling::Error) do
        LoreReleaseTooling.verify_review_item_versions!(ids, expected_version_id: "expected")
      end
    end
    assert LoreReleaseTooling.verify_review_item_versions!(["expected"], expected_version_id: "expected")
    %w[submit_for_review swap_latest_build_and_resubmit].each do |lane|
      body = lane_body(lane)
      assert_operator body.index("verify_review_submission_version!"), :<, body.index("submission.submit_for_review")
    end
  end

  def test_build_selection_uses_exact_tuple_instead_of_newest
    expected = valid_build
    assert_same expected, release_target.select_build!([valid_build(version: "49"), expected], app_id: "123")
    assert_raises(LoreReleaseTooling::Error) { release_target.select_build!([valid_build(version: "49")], app_id: "123") }
    assert_raises(LoreReleaseTooling::Error) { release_target.select_build!([expected, valid_build], app_id: "123") }
  end

  def test_release_build_must_belong_to_same_app_platform_and_marketing_version
    [{ version: "49" }, { app_version: "1.1" }, { app_id: "456" }, { platform: "MAC_OS" }].each do |override|
      assert_raises(LoreReleaseTooling::Error) { release_target.verify_build!(valid_build(**override), app_id: "123") }
    end
  end

  def test_release_build_must_be_valid_and_explicitly_nonexpired
    [{ processing_state: "PROCESSING" }, { processing_state: "INVALID" }, { expired: true },
     { expired: nil }, { expiration_date: "2020-01-01T00:00:00Z" }, { expiration_date: "bad-date" }].each do |override|
      assert_raises(LoreReleaseTooling::Error) { release_target.verify_build!(valid_build(**override), app_id: "123") }
    end
    assert release_target.verify_build!(valid_build, app_id: "123")
  end

  def test_beta_build_is_monotonic_across_a_new_marketing_version
    assert_equal 48, LoreReleaseTooling.next_build_number(project_floor: "48", latest: 0)
    assert_equal 48, LoreReleaseTooling.next_build_number(project_floor: 48, latest: 47)
    assert_equal 50, LoreReleaseTooling.next_build_number(project_floor: 48, latest: 49)
    assert_raises(LoreReleaseTooling::Error) { LoreReleaseTooling.next_build_number(project_floor: 48, latest: "unknown") }
  end

  def test_app_and_widget_must_share_the_release_version_and_floor
    Dir.mktmpdir do |directory|
      path = File.join(directory, "project.yml")
      target = { "settings" => { "base" => { "MARKETING_VERSION" => "1.2", "CURRENT_PROJECT_VERSION" => "48" } } }
      File.write(path, { "targets" => { "Lore" => target, "LoreWidget" => Marshal.load(Marshal.dump(target)) } }.to_yaml)
      assert_equal({ version: "1.2", build_floor: 48 }, LoreReleaseTooling.project_release_settings(path))
      # Construct a clear mismatch without depending on YAML's quoting style.
      data = YAML.load_file(path)
      data["targets"]["LoreWidget"]["settings"]["base"]["CURRENT_PROJECT_VERSION"] = "47"
      File.write(path, data.to_yaml)
      assert_raises(LoreReleaseTooling::Error) { LoreReleaseTooling.project_release_settings(path) }
    end
  end

  def test_checked_in_release_configuration_has_matching_targets_and_release_notes
    settings = LoreReleaseTooling.project_release_settings(File.expand_path("../../project.yml", __dir__))
    version = LoreReleaseTooling.release_version!(settings.fetch(:version), project_version: settings.fetch(:version))
    notes = File.read(File.expand_path("../release_notes/#{version}.en-US.txt", __dir__)).strip
    assert (1..4000).cover?(notes.length), "The project version needs nonempty App Store release notes of at most 4000 characters"
    assert_operator settings.fetch(:build_floor), :>, 0
  end

  def test_submission_and_auto_release_require_exact_target_before_authentication
    %w[select_release_build submit_for_review swap_latest_build_and_resubmit set_auto_release].each do |lane|
      body = lane_body(lane)
      assert_operator body.index("expected_release_target!"), :<, body.index("asc_token!")
      assert_includes body, "verify_attached_release_build!"
    end
    refute_includes lane_body("swap_latest_build_and_resubmit"), 'limit: 1'
    refute_match(/^\s*app\.ensure_version!/, lane_body("prepare_version"))
  end

  def test_product_catalog_uses_get_only_and_follows_pages
    response_class = Struct.new(:body, :following_pages) do
      def all_pages = [self] + Array(following_pages)
    end
    calls = []
    client = Object.new
    client.define_singleton_method(:get) do |path, _params|
      calls << path
      data = case path
             when "v1/apps/123/subscriptionGroups"
               [{ "id" => "group" }]
             when "v1/subscriptionGroups/group/subscriptions"
               [{ "id" => "monthly", "type" => "subscriptions", "attributes" => { "productId" => "lore_plus_monthly", "state" => "APPROVED" } }]
             when "v1/apps/123/inAppPurchasesV2"
               [{ "id" => "lifetime", "type" => "inAppPurchases", "attributes" => { "productId" => "lore_plus_lifetime", "state" => "READY_TO_SUBMIT" } }]
             else raise "Unexpected endpoint #{path}"
             end
      following_pages = if path == "v1/subscriptionGroups/group/subscriptions"
                          [response_class.new({ "data" => [{ "id" => "annual", "type" => "subscriptions", "attributes" => { "productId" => "lore_plus_annual", "state" => "APPROVED" } }] })]
                        end
      response_class.new({ "data" => data }, following_pages)
    end
    rows = LoreReleaseTooling.product_catalog(client, app_id: "123")
    assert_equal %w[lore_plus_monthly lore_plus_annual lore_plus_lifetime], rows.map { |row| row[:product_id] }
    assert_equal %w[APPROVED APPROVED READY_TO_SUBMIT], rows.map { |row| row[:state] }
    assert_equal 3, calls.length
    assert_includes lane_body("preflight"), "LoreReleaseTooling.product_catalog"
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
