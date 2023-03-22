# frozen_string_literal: true

# rubocop:disable Rails/Output
require 'csv'
require 'optparse'
begin
  require 'reporting/cloudwatch_client'
  require 'reporting/cloudwatch_query_quoting'
rescue LoadError => e
  warn 'could not load paths, try running with "bundle exec rails runner"'
  raise e
end

module Reporting
  class IdentityVerificationReport
    include Reporting::CloudwatchQueryQuoting

    attr_reader :issuer, :date

    module Events
      IDV_DOC_AUTH_IMAGE_UPLOAD = 'IdV: doc auth image upload vendor submitted'
      IDV_GPO_ADDRESS_LETTER_REQUESTED = 'IdV: USPS address letter requested'
      USPS_IPP_ENROLLMENT_CREATED = 'USPS IPPaaS enrollment created'
      IDV_FINAL_RESOLUTION = 'IdV: final resolution'
      GPO_VERIFICATION_SUBMITTED = 'IdV: GPO verification submitted'
      USPS_ENROLLMENT_STATUS_UPDATED = 'GetUspsProofingResultsJob: Enrollment status updated'

      def self.all_events
        constants.map { |c| const_get(c) }
      end
    end

    # @param [String] isssuer
    # @param [Date] date
    def initialize(issuer:, date:, verbose: false, progress: false)
      @issuer = issuer
      @date = date
      @verbose = verbose
      @progress = progress
    end

    def verbose?
      @verbose
    end

    def progress?
      @progress
    end

    def to_csv
      CSV.generate do |csv|
        csv << ['Report Timeframe', "#{from} to #{to}"]
        csv << ['Report Generated', Date.today.to_s] # rubocop:disable Rails/Date
        csv << ['Issuer', issuer]
        csv << []
        csv << ['Metric', '# of Users']
        csv << ['Started IdV Verification', idv_doc_auth_image_vendor_submitted]
        csv << ['Incomplete Users', incomplete_users]
        csv << ['Address Confirmation Letters Requested', idv_gpo_address_letter_requested]
        csv << ['Started In-Person Verification', usps_ipp_enrollment_created]
        csv << ['Alternative Process Users', alternative_process_users]
        csv << ['Success through Online Verification', idv_final_resolution]
        csv << ['Success through Address Confirmation Letters', gpo_verification_submitted]
        csv << ['Success through In-Person Verification', usps_enrollment_status_updated]
        csv << ['Successfully Verified Users', successfully_verified_users]
      end
    end

    def incomplete_users
      idv_doc_auth_image_vendor_submitted - successfully_verified_users - alternative_process_users
    end

    def idv_gpo_address_letter_requested
      data[Events::IDV_GPO_ADDRESS_LETTER_REQUESTED].to_i
    end

    def usps_ipp_enrollment_created
      data[Events::USPS_IPP_ENROLLMENT_CREATED].to_i
    end

    def alternative_process_users
      [
        idv_gpo_address_letter_requested,
        usps_ipp_enrollment_created,
        -gpo_verification_submitted,
        -usps_enrollment_status_updated,
      ].sum
    end

    def idv_final_resolution
      data[Events::IDV_FINAL_RESOLUTION].to_i
    end

    def gpo_verification_submitted
      data[Events::GPO_VERIFICATION_SUBMITTED].to_i
    end

    def usps_enrollment_status_updated
      data[Events::USPS_ENROLLMENT_STATUS_UPDATED].to_i
    end

    def successfully_verified_users
      idv_final_resolution + gpo_verification_submitted + usps_enrollment_status_updated
    end

    def idv_doc_auth_image_vendor_submitted
      data[Events::IDV_DOC_AUTH_IMAGE_UPLOAD].to_i
    end

    # Turns query results into a hash keyed by event name, values are a count of unique users
    # for that event
    # @return [Hash<String,Integer>]
    def data
      @data ||= begin
        event_users = Hash.new do |h, uuid|
          h[uuid] = Set.new
        end

        # IDEA: maybe there's a block form if this we can do that yields results as it loads them
        # to go slightly faster
        fetch_results.each do |row|
          event_users[row['name']] << row['user_id']
        end

        event_users.transform_values(&:count)
      end
    end

    def fetch_results
      cloudwatch_client.fetch(query:, from:, to:)
    end

    # @return [Time]
    def from
      date.in_time_zone('UTC').beginning_of_day
    end

    # @return [Time]
    def to
      date.in_time_zone('UTC').end_of_day
    end

    def query
      params = {
        issuer: quote(issuer),
        event_names: quote(Events.all_events),
        usps_enrollment_status_updated: quote(Events::USPS_ENROLLMENT_STATUS_UPDATED),
        gpo_verification_submitted: quote(Events::GPO_VERIFICATION_SUBMITTED),
        idv_final_resolution: quote(Events::IDV_FINAL_RESOLUTION),
      }

      format(<<~QUERY, params)
        fields
            name
          , properties.user_id AS user_id
        | filter properties.service_provider = %{issuer}
        | filter name in %{event_names}
        | filter (name = %{usps_enrollment_status_updated} and properties.event_properties.passed = 1)
                 or (name != %{usps_enrollment_status_updated})
        | filter (name = %{gpo_verification_submitted} and properties.event_properties.success = 1)
                 or (name != %{gpo_verification_submitted})
        | filter (name = %{idv_final_resolution} and isblank(properties.event_properties.deactivation_reason))
                 or (name != %{idv_final_resolution})
        | limit 10000
      QUERY
    end

    def cloudwatch_client
      @cloudwatch_client ||= Reporting::CloudwatchClient.new(
        ensure_complete_logs: true,
        slice_interval: 3.hours,
        progress: progress?,
        logger: verbose? ? Logger.new(STDERR) : nil,
      )
    end

    # rubocop:disable Rails/Exit
    # @return [Hash]
    def self.parse!(argv, out: STDOUT)
      date = nil
      issuer = nil
      verbose = false
      progress = true

      program_name = Pathname.new($PROGRAM_NAME).relative_path_from(__dir__)

      parser = OptionParser.new do |opts|
        opts.banner = <<~TXT
          Usage:

          #{program_name} --date YYYY-MM-DD --issuer ISSUER

          Options:
        TXT

        opts.on('--date=DATE', 'date to run the report in YYYY-MM-DD format') do |date_v|
          date = Date.parse(date_v)
        end

        opts.on('--issuer=ISSUER') do |issuer_v|
          issuer = issuer_v
        end

        opts.on('--[no-]verbose', 'log details STDERR, default to off') do |verbose_v|
          verbose = verbose_v
        end

        opts.on('--[no-]progress', 'shows a progress bar or hides it, defaults on') do |progress_v|
          progress = progress_v
        end

        opts.on('-h', '--help') do
          out.puts opts
          exit 1
        end
      end

      parser.parse!(argv)

      if !date || !issuer
        out.puts parser
        exit 1
      end

      {
        date: date,
        issuer: issuer,
        verbose: verbose,
        progress: progress,
      }
    end
    # rubocop:enable Rails/Exit
  end
end

if __FILE__ == $PROGRAM_NAME
  options = Reporting::IdentityVerificationReport.parse!(ARGV)

  puts Reporting::IdentityVerificationReport.new(**options).to_csv
end
# rubocop:enable Rails/Output