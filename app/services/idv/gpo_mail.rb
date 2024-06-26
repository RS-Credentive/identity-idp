# frozen_string_literal: true

module Idv
  class GpoMail
    attr_reader :current_user

    def initialize(current_user)
      @current_user = current_user
    end

    def rate_limited?
      too_many_letter_requests_within_window? || last_letter_request_too_recent?
    end

    def profile_too_old?
      return false if !current_user.pending_profile

      min_creation_date = IdentityConfig.store.
        gpo_max_profile_age_to_send_letter_in_days.days.ago

      current_user.pending_profile.created_at < min_creation_date
    end

    private

    def window_limit_enabled?
      IdentityConfig.store.max_mail_events != 0 &&
        IdentityConfig.store.max_mail_events_window_in_days != 0
    end

    def last_not_too_recent_enabled?
      IdentityConfig.store.minimum_wait_before_another_usps_letter_in_hours != 0
    end

    def too_many_letter_requests_within_window?
      return false unless window_limit_enabled?
      current_user.gpo_confirmation_codes.where(
        created_at: IdentityConfig.store.max_mail_events_window_in_days.days.ago..Time.zone.now,
      ).count >= IdentityConfig.store.max_mail_events
    end

    def last_letter_request_too_recent?
      return false unless last_not_too_recent_enabled?
      return false unless current_user.gpo_verification_pending_profile?

      current_user.gpo_verification_pending_profile.gpo_confirmation_codes.exists?(
        [
          'created_at > ?',
          IdentityConfig.store.minimum_wait_before_another_usps_letter_in_hours.hours.ago,
        ],
      )
    end
  end
end
