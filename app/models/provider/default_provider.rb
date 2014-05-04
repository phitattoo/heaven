module Provider
  class DefaultProvider
    include ApiClient
    include LocalLogFile

    attr_accessor :guid, :name, :payload

    def initialize(guid, payload)
      @guid    = guid
      @name    = "unknown"
      @payload = payload
    end

    def data
      @data ||= JSON.parse(payload)
    end

    def output
      @output ||= Deployment::Output.new(app_name, number, guid)
    end

    def status
      @status ||= Deployment::Status.new(name_with_owner, number)
    end

    def redis
      Heaven.redis
    end

    def number
      data['id']
    end

    def name
      custom_payload_name || name_with_owner
    end

    def name_with_owner
      data['repository']['full_name']
    end

    def sha
      data['sha'][0..7]
    end

    def ref
      data['ref']
    end

    def environment
      data['environment']
    end

    def repository_url
      data['repository']['clone_url']
    end

    def default_branch
      data['repository']['default_branch']
    end

    def clone_url
      uri = Addressable::URI.parse(repository_url)
      uri.user = github_token
      uri.password = ""
      uri.to_s
    end

    def custom_payload
      @custom_payload ||= data['payload']
    end

    def custom_payload_name
      custom_payload && custom_payload['name']
    end

    def custom_payload_config
      custom_payload && custom_payload['config']
    end

    def setup
      output.create
      status.output = output.url
      status.pending!
    end

    def completed?
      status.completed?
    end

    def execute
      warn "Heaven Provider(#{name}) didn't implement execute"
    end

    def notify
      warn "Heaven Provider(#{name}) didn't implement notify"
    end

    def record
      Deployment.create(:custom_payload  => JSON.dump(custom_payload),
                        :environment     => environment,
                        :guid            => guid,
                        :name            => name,
                        :name_with_owner => name_with_owner,
                        :output          => output.url,
                        :ref             => ref,
                        :sha             => sha)
    end

    def timeout
      Integer(ENV['DEPLOYMENT_TIMEOUT'] || '300')
    end

    def run!
      Timeout.timeout(timeout) do
        setup
        execute
        notify
        record
      end
    rescue StandardError => e
      Rails.logger.info e.message
      Rails.logger.info caller
    ensure
      status.failure! unless completed?
    end
  end
end
