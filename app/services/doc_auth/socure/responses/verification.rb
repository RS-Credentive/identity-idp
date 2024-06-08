# frozen_string_literal: true

module DocAuth
  module Socure
    module Responses
      class Verification < DocAuth::Response
        include DocPiiReader
        # include ClassificationConcern

        attr_reader :payload

        def initialize(payload)
          @payload = payload
          @liveness_checking_enabled = false
          @pii_from_doc = read_pii(document_verification_data)
          super(
            success: successful_result?,
            errors: error_messages,
            extra: extra_attributes,
            pii_from_doc: @pii_from_doc,
          )
        rescue StandardError => e
          NewRelic::Agent.notice_error(e)
          super(
            success: false,
            errors: { network: true },
            exception: e,
            extra: {
              backtrace: e.backtrace,
              reference: payload['referenceId'],
            },
          )
        end

        def successful_result?
          doc_auth_success?
        end

        def doc_auth_success?
          return false unless id_type_supported?

          document_verification_data.dig('decision', 'value') == 'accept'
        end

        def error_messages
          return {} if successful_result?

          document_verification_data['reasonCodes'] # may need to be hash
        end

        def extra_attributes
          document_verification_data.except('documentData')
        end

        def attention_with_barcode?
          false
        end

        def billed?
          true # tbd
        end

        private

        def document_verification_data
          payload.dig('data', 'documentVerification')
        end

        def id_type_supported?
          true # tbd
        end
      end
    end
  end
end
