require 'rails_helper'

feature 'idv gpo otp verification step', :js do
  include IdvStepHelper

  let(:otp) { 'ABC123' }
  let(:profile) do
    create(
      :profile,
      deactivation_reason: :gpo_verification_pending,
      pii: { ssn: '123-45-6789', dob: '1970-01-01' },
      proofing_components: {
        threatmetrix: threatmetrix_enabled,
        threatmetrix_review_status: threatmetrix_review_status,
      },
    )
  end
  let(:gpo_confirmation_code) do
    create(
      :gpo_confirmation_code,
      profile: profile,
      otp_fingerprint: Pii::Fingerprinter.fingerprint(otp),
    )
  end
  let(:user) { profile.user }
  let(:threatmetrix_enabled) { false }
  let(:threatmetrix_review_status) { nil }
  let(:redirect_after_verification) { nil }
  let(:profile_should_be_active) { true }
  let(:fraud_review_pending) { false }

  before do
    allow(IdentityConfig.store).to receive(:proofing_device_profiling).
      and_return(threatmetrix_enabled ? :enabled : :disabled)
  end

  it_behaves_like 'gpo otp verification'

  context 'ThreatMetrix disabled, but we have ThreatMetrix status on proofing component' do
    let(:threatmetrix_enabled) { false }
    let(:threatmetrix_review_status) { 'review' }
    it_behaves_like 'gpo otp verification'
  end

  context 'ThreatMetrix enabled' do
    let(:threatmetrix_enabled) { true }

    context 'ThreatMetrix says "pass"' do
      let(:threatmetrix_review_status) { 'pass' }
      it_behaves_like 'gpo otp verification'
    end

    context 'ThreatMetrix says "review"' do
      let(:threatmetrix_review_status) { 'review' }
      let(:redirect_after_verification) { idv_please_call_path }
      let(:profile_should_be_active) { false }
      let(:fraud_review_pending) { true }
      it_behaves_like 'gpo otp verification'
    end

    context 'ThreatMetrix says "reject"' do
      let(:threatmetrix_review_status) { 'reject' }
      let(:redirect_after_verification) { idv_please_call_path }
      let(:profile_should_be_active) { false }
      let(:fraud_review_pending) { true }
      it_behaves_like 'gpo otp verification'
    end

    context 'No ThreatMetrix result on proofing component' do
      let(:threatmetrix_review_status) { nil }
      it_behaves_like 'gpo otp verification'
    end
  end

  context 'with gpo personal key after verification' do
    it 'shows the user a personal key after verification' do
      sign_in_live_with_2fa(user)

      expect(current_path).to eq idv_gpo_verify_path
      expect(page).to have_content t('idv.messages.gpo.resend')

      gpo_confirmation_code
      fill_in t('forms.verify_profile.name'), with: otp
      click_button t('forms.verify_profile.submit')

      profile.reload

      expect(page).to have_current_path(idv_personal_key_path)

      expect(profile.active).to be(true)
      expect(profile.deactivation_reason).to be(nil)

      expect(user.events.account_verified.size).to eq 1
    end
  end

  context 'with gpo feature disabled' do
    before do
      allow(IdentityConfig.store).to receive(:gpo_verification_enabled?).and_return(true)
    end

    it 'allows a user to verify their account for an existing pending profile' do
      sign_in_live_with_2fa(user)

      expect(current_path).to eq idv_gpo_verify_path
      expect(page).to have_content t('idv.messages.gpo.resend')

      gpo_confirmation_code
      fill_in t('forms.verify_profile.name'), with: otp
      click_button t('forms.verify_profile.submit')

      expect(user.events.account_verified.size).to eq 1
      expect(page).to_not have_content(t('account.index.verification.reactivate_button'))
    end
  end
end
