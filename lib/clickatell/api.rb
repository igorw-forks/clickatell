module Clickatell
  # This module provides the core implementation of the Clickatell
  # HTTP service.
  class API
    attr_accessor :auth_options

    class << self
      # Authenticates using the given credentials and returns an
      # API instance with the authentication options set to use the
      # resulting session_id.
      def authenticate(api_id, username, password)
        api = self.new({
          :api_id   => api_id,
          :username => username,
          :password => password,
        })
        api.authenticate
        api
      end

      # Set to true to enable debugging (off by default)
      attr_accessor :debug_mode

      # Enable secure mode (SSL)
      attr_accessor :secure_mode

      # Allow customizing URL
      attr_accessor :api_service_host

      # Set to your HTTP proxy details (off by default)
      attr_accessor :proxy_host, :proxy_port, :proxy_username, :proxy_password

      # Set to true to test message sending; this will not actually send
      # messages but will collect sent messages in a testable collection.
      # (off by default)
      attr_accessor :test_mode
    end
    self.debug_mode = false
    self.secure_mode = false
    self.test_mode = false

    # Creates a new API instance using the specified +auth options+.
    # +auth_options+ is a hash containing either a :session_id or
    # :auth_options.
    #
    # Some API calls (authenticate, ping etc.) do not require any
    # +auth_options+. +auth_options+ can be updated using the accessor methods.
    def initialize(auth_options={})
      @auth_options = auth_options
    end

    # Authenticates using the specified credentials. Returns
    # a session_id if successful which can be used in subsequent
    # API calls.
    def authenticate
      response = execute_command('auth', 'http', {}, true)
      @auth_options[:session_id] = parse_response(response)['OK']
    end

    # Pings the service with the specified session_id to keep the
    # session alive.
    def ping(session_id)
      execute_command('ping', 'http', :session_id => session_id)
    end

    # Sends a message +message_text+ to +recipient+. Recipient
    # number should have an international dialing prefix and
    # no leading zeros (unless you have set a default prefix
    # in your clickatell account centre).
    #
    # Messages over 160 characters are split into multiple messages automatically,
    # and the :concact option will be set, overwriting any manual value of this option.
    #
    # You normally wouldn't need to set :concat manually and can rely on the automatica
    # splitting behaviour.
    #
    # Additional options:
    #    :from - the from number/name
    #    :set_mobile_originated - mobile originated flag
    #    :client_message_id - user specified message id that can be used in place of Clickatell issued API message ID for querying message
    #    :concat - number of concatenations allowed. I.E. how long is a message allowed to be.
    # Returns a new message ID if successful.
    def send_message(recipient, message_text, opts={})
      valid_options = opts.only(:from, :mo, :callback, :climsgid, :concat)
      valid_options.merge!(:req_feat => '48') if valid_options[:from]
      valid_options.merge!(:mo => '1') if opts[:set_mobile_originated]
      valid_options.merge!(:climsgid => opts[:client_message_id]) if opts[:client_message_id]
      if message_text.length > 160
        valid_options.merge!(:concat => (message_text.length.to_f / 160).ceil)
      end
      recipient = recipient.join(",")if recipient.is_a?(Array)
      response = execute_command('sendmsg', 'http',
        {:to => recipient, :text => message_text}.merge(valid_options)
      )
      response = parse_response(response)
      response.is_a?(Array) ? response.map { |r| r['ID'] } : response['ID']
    end

    def send_wap_push(recipient, media_url, notification_text='', opts={})
      valid_options = opts.only(:from)
      valid_options.merge!(:req_feat => '48') if valid_options[:from]
      response = execute_command('si_push', 'mms',
        {:to => recipient, :si_url => media_url, :si_text => notification_text, :si_id => 'foo'}.merge(valid_options)
      )
      parse_response(response)['ID']
    end

    # Returns the status of a message. Use message ID returned
    # from original send_message call.
    def message_status(message_id)
      response = execute_command('querymsg', 'http', :apimsgid => message_id)
      parse_response(response)['Status']
    end

    def message_charge(message_id)
      response = execute_command('getmsgcharge', 'http', :apimsgid => message_id)
      parse_response(response)['charge'].to_f
    end

    # Returns the number of credits remaining as a float.
    def account_balance
      response = execute_command('getbalance', 'http')
      parse_response(response)['Credit'].to_f
    end

    def sms_requests
      @sms_requests ||= []
    end

    # NOTE: OTP API is still beta and requires registration
    # send one time password to recipient
    # returns message_id
    def send_otp(recipient, message_text=nil)
      message_text = 'Your password is #OTP#' if !message_text
      response = execute_command('sendotp', 'http', {
        :to => recipient,
        :text => message_text
      }, true)
      parse_response(response)['ID']
    end

    # NOTE: OTP API is still beta and requires registration
    # verify one time password
    # optionally activate sender
    def verify_otp(recipient, otp, message_id, activate_sender=false)
      response = execute_command('verifyotp', 'http', {
        :to => recipient,
        :otp => otp,
        :apiMsgId => message_id,
        :sender_id => activate_sender ? 1 : 0
      }, true)
      parse_response(response)['OK']
    end

    protected
      def execute_command(command_name, service, parameters={}, no_session = false) #:nodoc:
        executor = CommandExecutor.new(auth_extra_params(no_session), self.class.secure_mode, self.class.debug_mode, self.class.test_mode)
        result = executor.execute(command_name, service, parameters)

        (sms_requests << executor.sms_requests).flatten! if self.class.test_mode

        result
      end

      def parse_response(raw_response) #:nodoc:
        Clickatell::Response.parse(raw_response)
      end

      def auth_extra_params(no_session = false) #:nodoc:
        credentials = {
          :api_id   => @auth_options[:api_id],
          :user     => @auth_options[:username],
          :password => @auth_options[:password],
        }

        if no_session
          credentials
        elsif @auth_options[:session_id]
          { :session_id => @auth_options[:session_id] }
        elsif @auth_options[:api_id]
          credentials
        else
          {}
        end
      end
  end
end

%w( api/command
    api/command_executor
    api/error
    api/message_status

).each do |lib|
    require File.join(File.dirname(__FILE__), lib)
end
