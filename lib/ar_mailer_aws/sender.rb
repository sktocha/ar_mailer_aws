require 'aws-sdk'

module ArMailerAWS
  class Sender
    attr_reader :options, :model, :ses

    def initialize(options={})
      @options = options.is_a?(Hash) ? OpenStruct.new(options) : options
      @model = ArMailerAWS.email_class.constantize
      @ses = AWS::SimpleEmailService.new ArMailerAWS.ses_options
    end

    def send_batch
      cleanup
      emails = find_emails
      log "found #{emails.length} emails to deliver"
      send_emails(emails) unless emails.empty?
    end

    def send_emails(emails)
      emails.each do |email|
        log "send email to #{email.to}"
        begin
          @ses.send_raw_email email.mail, from: email.from, to: email.to
          email.destroy
        rescue => e
          log "ERROR sending email #{email.id} - #{email.inspect}", :error
          ArMailerAWS.error_proc.call(email, e) if ArMailerAWS.error_proc
          email.update_column(:last_send_attempt_at, Time.now)
        end
      end
    end

    def find_emails
      @model.where('last_send_attempt_at IS NULL OR last_send_attempt_at < ?', Time.now - 300).limit(options.batch_size)
    end

    def cleanup
      return if options.max_age.zero?
      timeout = Time.now - options.max_age
      emails = @model.destroy_all(['last_send_attempt_at IS NOT NULL AND created_at < ?', timeout])

      log "expired #{emails.length} emails"
    end

    def log(msg, level=:info)
      formatted_msg = "[#{Time.now}] ar_mailer_aws: #{msg}"
      puts formatted_msg if options.verbose
      if logger
        logger.send(level, msg)
      else
        Rails.logger.send(level, formatted_msg) if options.verbose && defined? Rails
      end
    end

    def logger
      ArMailerAWS.logger
    end
  end
end
